//===- VedaShadowPropagation.cpp -----------------------------------------===//
//
// Toolchain Milestone 8: SoftBound-style (PLDI 2009, disjoint shadow
// -metadata) IR pass, phase 1 -- shadow Object_ID propagation. Proves (and
// makes FileCheck-observable) that a shadow i32 Object_ID value is
// correctly tracked alongside every pointer value provably derived from
// @veda_malloc_raw, through:
//   1. straight-line pointer arithmetic (getelementptr / pointer bitcast)
//   2. a memory round-trip (store then load)
//   3. function-call argument passing
//   4. phi-node control-flow merges (including loop-carried/cyclic ones)
//
// Toolchain Milestone 9 extends the SAME pass with phase 2: real
// dereference codegen -- rewriting an actual load/store whose ADDRESS is
// itself a tracked (object-relative) pointer into a real veda_rt_ocl_d/
// veda_rt_ocs_d runtime call, using the tracked object's real Object_ID
// and a byte offset computed directly from the pointer's own numeric
// value (see "the pointer-as-offset-token representation" below).
//
// A real, deliberate simplification from original SoftBound, already
// agreed in this project's own toolchain plan: a single opaque Object_ID
// scalar is propagated, not a base+bound pair -- bounds checking is real
// hardware's own job here (the ODT, veda_check_access), not the
// compiler's.
//
// The pointer-as-offset-token representation (Milestone 9's own real
// design decision, made after working through what an actual end-to-end
// linked-list demo needs): @veda_malloc_raw's returned "ptr" component is
// NOT a real, dereferenceable machine address -- Milestone 9's real
// runtime always returns the fixed, non-null sentinel kVedaNullBase
// (0x1000; deliberately non-null so no LLVM optimization pass is ever
// tempted to treat pointer arithmetic on it as null-pointer-dereference
// UB) as a common "zero" base for every fresh object. Every subsequent
// GEP naturally accumulates the real byte offset within that object as
// the pointer's own bit pattern (ptrtoint(p) - kVedaNullBase), since nothing
// about GEP's own address arithmetic cares whether the "base" is a real
// address or not. This is coherent specifically because no tracked
// pointer is EVER dereferenced via a real load/store instruction in the
// final program -- Milestone 9's own dereference-rewrite rule (below)
// intercepts every such access before it would ever reach real memory
// through the raw pointer value, redirecting through real OCL.D/OCS.D via
// (Object_ID, offset) instead. Matches VEDA_CORE_SPEC.md's own real
// architecture exactly: "software holds an opaque Object_ID, never a raw
// address" -- the IR-level pointer here is a compiler-internal offset
// -tracking device, not a real address, and after this pass runs, no real
// address is ever computed for accessing a tracked object at all.
//
// Recognized runtime ABI:
//   declare ptr @veda_malloc_raw(i64, ptr)   -- object_id written through
//     the 2nd (out-param) argument, NOT a struct return. A real, deliberate
//     revision from this pass's own original Milestone 8 design (which
//     used `{ptr,i32}` struct-return + extractvalue): empirically verified
//     (compiling a real minimal C source through this exact clang/riscv64
//     -lp64 build) that a `{void*,uint32_t}` C struct return gets ABI
//     -coerced by clang into a completely different IR shape (`[2 x i64]`,
//     round-tripped through a stack alloca+GEP, not a clean `extractvalue`
//     at all) -- the pass's original hand-written `.ll` tests happened to
//     use the un-coerced shape directly and would never have caught this
//     real, would-be-silent gap against actual compiled C source. An
//     out-parameter avoids struct-return ABI coercion entirely and was
//     independently verified to produce the simple, predictable
//     `call ptr @veda_malloc_raw(...)` shape below.
//   declare void @veda_shadow_store(ptr, i32)
//   declare i32  @veda_shadow_load(ptr)
//   declare void @veda_shadow_attach(ptr, i32)   -- observability marker only,
//     inserted after every point a Value's shadow becomes newly known;
//     real precedent for this kind of analysis-observability marker call
//     is llvm.dbg.value's own real role.
//   declare void @veda_rt_ocl_d(i32, i64, ptr)   -- Milestone 9: object_id,
//     byte offset, out-param slot. Real hardware backing: OCL.D via
//     Milestone 7's veda_rt_asm.S primitives (see veda-core/compiler/
//     veda_compiler_rt.c).
//   declare void @veda_rt_ocs_d(i32, i64, i64)   -- Milestone 9: object_id,
//     byte offset, 8-byte value. Real hardware backing: OCS.D.
//   declare void @veda_rt_ocl_stack_d(i64, i64, i64, ptr)  -- Toolchain
//     Milestone 12: region_offset, access_offset, size, out-param slot.
//     Protects `alloca`-based C local variables (not heap objects) inside
//     a veda_compartment function, backed by the SSC region already
//     established in C15 (Toolchain Milestone 11) -- no Object_ID, since
//     the target is always the already-bound C15, never a fresh
//     veda.bind. Real hardware backing: OCA (position to region_offset
//     within C15's whole region) then CSetBounds (narrow to exactly
//     `size` bytes, this alloca's own allocation size) then OCL.D against
//     the resulting narrowed, positioned capability -- see
//     veda_rt_asm.S's own veda_ocl_stack_d_scratch_asm.
//   declare void @veda_rt_ocs_stack_d(i64, i64, i64, i64)  -- mirror, OCS.D.
//
// Toolchain Milestone 12's own real, honest scope, matching real CHERI-
// LLVM's own actual default (`CBM_Conservative`, CHERI C/C++ Programming
// Guide Section 4.3.3 -- verified against the official guide, not
// assumed): this protects SEPARATE local variables from overflowing into
// each other (e.g. `int lower[4]; int upper[4];`), not fields WITHIN one
// single allocation from each other (subobject bounds, e.g. a struct's
// own internal array field overflowing into an adjacent field of that
// same struct) -- real CHERI itself does not enable that by default
// either, for the identical, documented compatibility reasons. Only
// entry-block, static (fixed-size) allocas are recognized -- a
// dynamic-size (VLA) alloca, or one placed outside the entry block, is
// left completely unrewritten (zero protection, not degraded protection,
// matching this pass's own established convention for untracked
// addresses elsewhere).
//
// A real, honest, hardware-forced width limit (not a simplification of
// convenience): Milestone 9's dereference rewrite only handles 64-bit
// -wide (i64 or pointer-typed) loads/stores on a tracked address. This
// directly matches a real fact already confirmed from Sail source in
// Milestone 5b/M6: Veda-Core's own real ISA has no OCL.B/H/W or
// OCS.B/H/W variants at all -- only the `.D` (8-byte) and `.C` (128-byte
// capability) widths exist. A narrower/wider tracked access is left as an
// ordinary, unrewritten load/store (real, honest, stated Phase-2 gap);
// Milestone 9's own demo source is written to only use 64-bit-wide struct
// fields for exactly this reason.
//
// A real, additional propagation rule discovered as NECESSARY (not
// originally in Milestone 8's own four cases) while working through what
// a genuine linked-list traversal demo requires: `icmp eq/ne ptr %X,
// null` where %X is a tracked pointer is rewritten to compare %X's shadow
// Object_ID against the invalid-object sentinel instead of comparing the
// raw pointer bit pattern. This is a real correctness necessity under the
// offset-token representation above: a fresh object's own pointer value
// is `kVedaNullBase + 0` for EVERY object (not a unique, comparable-to
// -null "no object" value at all) -- raw-pointer null comparison would be
// meaningless for detecting "this linked-list link has no next node";
// only the shadow Object_ID (defaulting to the invalid-object sentinel
// for an untracked/genuinely-null value, matching every other default in
// this pass) carries that information correctly.
//
// Real, stated Phase-1/2 scope limits (not glossed over):
//   - Function-call shadow passing is via an appended trailing i32
//     parameter per pointer parameter (a signature rewrite), not
//     SoftBound's own real "shadow stack" scheme -- simpler, real,
//     correct for this milestone's own closed-system, no-indirect-calls
//     scope; a shadow-stack scheme is legitimate future work if/when
//     function pointers need supporting.
//   - Indirect calls (through a function pointer) are not instrumented --
//     shadow tracking simply stops at such a call, matching real
//     SoftBound's own behavior at any ABI boundary with uninstrumented
//     code.
//   - Shadow propagation THROUGH a callee's own return value back to its
//     caller (Toolchain Milestone 20): a module-defined, non-runtime
//     -helper function whose return type is a pointer is now ALSO given a
//     trailing return-shadow out-param (pointer-to-i32, appended after
//     every per-pointer-parameter shadow), generalizing the existing
//     veda_malloc_raw out-param convention -- see ReturnShadowParamIndex
//     and TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md's Test 2 for
//     the real empirical gap this closes.
//   - Memory-round-trip shadow storage (@veda_shadow_store/_load) is
//     unconditionally emitted for every pointer store/load in scope, not
//     narrowed by any points-to/alias analysis -- a real, conservative,
//     correct-but-not-yet-optimized choice.
//   - Only 64-bit-wide tracked dereferences are rewritten (see above) --
//     a real, hardware-forced limit, not a convenience simplification.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Operator.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace {

constexpr char kMallocRawName[] = "veda_malloc_raw";
constexpr char kShadowStoreName[] = "veda_shadow_store";
constexpr char kShadowLoadName[] = "veda_shadow_load";
constexpr char kShadowAttachName[] = "veda_shadow_attach";
constexpr char kOclFnName[] = "veda_rt_ocl_d";
constexpr char kOcsFnName[] = "veda_rt_ocs_d";
// Toolchain Milestone 12: stack-local (alloca) variants -- no Object_ID,
// since the target is always the already-established, persistent SSC
// capability in C15 (Toolchain Milestone 11), never a fresh veda.bind.
constexpr char kOclStackFnName[] = "veda_rt_ocl_stack_d";
constexpr char kOcsStackFnName[] = "veda_rt_ocs_stack_d";
// Toolchain Milestone 13: global/static variants -- (table_slot_offset,
// access_offset, size) -> i64 / void, no Object_ID (the table itself is
// consulted via OCL.C at runtime; the pass never sees an Object_ID for an
// individual global at all). See veda_rt_asm.S's own
// veda_ocl_global_d_scratch_asm for the real OCL.C-then-OCL.D/OCS.D
// sequence this dispatches to.
constexpr char kOclGlobalFnName[] = "veda_rt_ocl_global_d";
constexpr char kOcsGlobalFnName[] = "veda_rt_ocs_global_d";
// Sentinel for "no known/tracked shadow" -- reuses the exact convention
// already established by Toolchain Milestone 7's own VEDA_OBJ_INVALID
// (veda_rt.h), not a freshly invented value.
constexpr uint32_t kInvalidObjectId = 0xFFFFFFFFu;
// The fixed, non-null "zero offset" base every veda_malloc_raw call
// returns (see file header comment for the full real reasoning). Must
// match veda_compiler_rt.c's own VEDA_NULL_BASE exactly.
constexpr uint64_t kVedaNullBase = 0x1000;
// Synthetic shadow-table key tag for a value stored INTO a tracked
// (object-relative) memory slot rather than a real machine address --
// see the "additional propagation rule" file-header discussion. Bit 63
// set is guaranteed disjoint from any real address in this bare-metal
// RV64 system (every real address here is in the low 0x80000000-ish
// 32-bit range).
constexpr uint64_t kSyntheticKeyTag = 1ULL << 63;

// Toolchain Milestone 12: FixedCSRFIMap (RISCVFrameLowering.cpp:63-68,
// personally re-verified against source before use) has exactly 13
// entries (ra, s0, s1, s2-s11), giving fixed offsets -8 through -104
// (-(RegNum+1)*8) -- permanently reserved for Milestone 11's own
// callee-saved-spill mechanism inside a veda_compartment function's SSC
// region. This IR-level pass runs entirely before the backend and has no
// visibility into RISCVFrameLowering.cpp's own table, so it must
// hardcode the identical numeric reservation as a pass-local constant.
// Must be re-verified if Milestone 11's own table ever changes.
constexpr int64_t kVedaCSRReservedBytes = 104;
// Matches veda_compartment_entry.S's own hardcoded `Length=0x1000` for
// the SSC region a compartment entry point establishes. A real,
// hand-maintained cross-file constant (same risk category as
// kVedaNullBase/VEDA_NULL_BASE above) -- if a future entry point ever
// changes its own Length, this must be updated by hand too.
constexpr int64_t kVedaSSCRegionLength = 4096;

// Toolchain Milestone 13: real, on-the-wire capability width
// (VEDA_CORE_SPEC.md Section 2 -- Tag(1,out-of-band)+128 data bits,
// OCL.C/OCS.C's own real access width, veda_ocl_insts.sail:130 "16 (bytes)
// = 128 bits") -- one capability-table slot is exactly this many bytes.
constexpr uint64_t kVedaCapTableSlotBytes = 16;
// Real linker-provided symbols (runtime/veda_rt.ld, this milestone's own
// addition, mirroring the file's existing __bss_start/__bss_end
// precedent) bounding the two source regions every table-resident
// per-global capability is OCA/CSetBounds-derived from once at bootstrap.
// __data_start..__bss_end is ONE contiguous span honestly over-covering
// the small .tohost gap the real linker script places between .data and
// .bss -- see that file's own comment for the full reasoning (harmless:
// an Object_ID's own bounds accounting never affects an ordinary,
// non-capability access to the same physical bytes).
constexpr char kRodataStartSym[] = "__rodata_start";
constexpr char kRodataEndSym[] = "__rodata_end";
constexpr char kDataStartSym[] = "__data_start";
constexpr char kBssEndSym[] = "__bss_end";

// One compile-time-computed row of the compiler-emitted bootstrap tuple
// table (Toolchain Milestone 13's own real, checked departure from
// CHERI's literal linker-emitted __cap_relocs mechanism -- see
// TOOLCHAIN_MILESTONE_13_DESIGN.md Section 3 for the full reasoning: this
// project's real linker/clang have no cap-reloc feature, so Phase B1
// itself computes and emits this table as ordinary compiler-generated
// data instead). `RegionOffset` is a Constant (a link-time-resolved
// symbol-difference expression, e.g. `ptrtoint(@g) - ptrtoint(@__data_start)`)
// rather than a plain integer, since the real numeric value is not known
// until the linker places both symbols.
struct VedaGlobalTableEntry {
  GlobalVariable *GV;
  bool IsRodata;
  Constant *RegionOffset;
  uint64_t Size;
  uint64_t SlotIndex;
};

class VedaShadowPropagation : public PassInfoMixin<VedaShadowPropagation> {
public:
  PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM);

private:
  LLVMContext *Ctx = nullptr;
  IntegerType *I32Ty = nullptr;
  IntegerType *I64Ty = nullptr;
  PointerType *PtrTy = nullptr;
  Constant *InvalidOid = nullptr;
  FunctionCallee ShadowStoreFn;
  FunctionCallee ShadowLoadFn;
  FunctionCallee ShadowAttachFn;
  FunctionCallee OclFn;
  FunctionCallee OcsFn;
  FunctionCallee OclStackFn;
  FunctionCallee OcsStackFn;
  FunctionCallee OclGlobalFn;
  FunctionCallee OcsGlobalFn;

  // Toolchain Milestone 13: Phase B1's own module-wide result -- every
  // qualifying global's real byte size and its assigned capability-table
  // slot BYTE offset (SlotIndex * kVedaCapTableSlotBytes, precomputed here
  // so propagateInFunction's own Load/Store dispatch never needs to
  // multiply). Populated once by propagateGlobals, consulted by every
  // later per-function propagateInFunction call -- the same
  // populate-module-wide-then-consult-per-function shape
  // PointerParamIndices below already establishes.
  DenseMap<GlobalVariable *, uint64_t> GlobalTableSlotOffset;
  DenseMap<GlobalVariable *, uint64_t> GlobalSize;

  // Per (already-rewritten) function: original parameter indices that are
  // pointer-typed, in the same order their shadow params were appended.
  // Populated by rewriteSignatures, consumed by propagateInFunction (both
  // for seeding a callee's own entry-point ShadowMap, and for fixing up
  // shadow arguments at every call site targeting that function).
  DenseMap<Function *, SmallVector<unsigned, 8>> PointerParamIndices;

  // Toolchain Milestone 20: return-value shadow propagation, closing the
  // real, previously-stated gap ("Shadow propagation THROUGH a callee's
  // own return value back to its caller is not yet implemented" -- see
  // file header, and TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md's
  // Test 2 for the real empirical demonstration this closes: a tracked
  // pointer returned by any module-defined function previously lost its
  // shadow at the call site, silently). Generalizes the EXACT out-param
  // convention this file's own veda_malloc_raw special case already uses
  // (Call->getArgOperand(1), an out-param the runtime writes the real
  // Object_ID through) to ordinary, module-defined, pointer-returning
  // functions: rewriteSignatures appends ONE trailing i32* out-param (in
  // addition to, and always AFTER, the existing per-pointer-parameter
  // shadow params) for any such function; this map records that
  // out-param's own argument index, keyed by the already-rewritten
  // Function. Absence from this map means F does not return a pointer (no
  // out-param was ever appended) -- checked via .find(), not .lookup(),
  // since index 0 is a real, valid index and cannot double as a "missing"
  // sentinel.
  DenseMap<Function *, unsigned> ReturnShadowParamIndex;

  static bool isRuntimeHelper(const Function &F) {
    StringRef N = F.getName();
    return N == kMallocRawName || N == kShadowStoreName ||
          N == kShadowLoadName || N == kShadowAttachName ||
          N == kOclFnName || N == kOcsFnName ||
          N == kOclStackFnName || N == kOcsStackFnName ||
          N == kOclGlobalFnName || N == kOcsGlobalFnName;
  }

  void attach(IRBuilder<> &B, Value *Ptr, Value *Shadow) {
    B.CreateCall(ShadowAttachFn, {Ptr, Shadow});
  }

  // Toolchain Milestone 13: find the GlobalVariable a Load/Store's own
  // pointer operand roots at, if any -- unlike Phase B0's AllocaBase (a
  // forward-propagation map populated instruction-by-instruction as Pass 2
  // visits each GEP/BitCast INSTRUCTION), a GlobalVariable's identity is
  // always directly recoverable from Addr's own structure at the
  // Load/Store site itself, with no separate propagation pass needed: a
  // constant-index global access is an inline GEP ConstantExpr (never a
  // real Instruction Pass 2's own per-instruction loop would ever visit),
  // so provenance must be read off Addr directly here instead.
  // dyn_cast<GEPOperator> is the real LLVM idiom that uniformly matches
  // BOTH a GetElementPtrInst (variable-index access, a real instruction)
  // and a GEP ConstantExpr (constant-index access) through one common
  // interface (confirmed against the real checked-out
  // llvm/include/llvm/IR/Operator.h before writing this). A direct
  // GlobalVariable operand (a scalar global, or element/field 0 of an
  // aggregate -- needs no GEP at all, offset 0 is the base address
  // itself) is the third, degenerate shape, handled by the first check.
  // Only single-level GEPs are handled -- a real, honest, narrow scope
  // limit (matching this pass's own established convention): a
  // multi-level GEP chain (e.g. a global array of structs, each
  // containing an array field) is left completely unrewritten rather
  // than attempting unverified multi-hop offset accumulation.
  GlobalVariable *findGlobalRoot(Value *Addr) {
    if (auto *GV = dyn_cast<GlobalVariable>(Addr))
      return GV;
    if (auto *GEPOp = dyn_cast<GEPOperator>(Addr))
      return dyn_cast<GlobalVariable>(GEPOp->getPointerOperand());
    return nullptr;
  }

  // Byte offset of a tracked pointer within its own object -- see the
  // pointer-as-offset-token discussion in the file header.
  Value *computeOffset(IRBuilder<> &B, Value *Addr) {
    Value *AsInt = B.CreatePtrToInt(Addr, I64Ty);
    return B.CreateSub(AsInt, ConstantInt::get(I64Ty, kVedaNullBase));
  }

  // Toolchain Milestone 12: a PHI merging pointers with AMBIGUOUS
  // provenance (some incoming values alloca-family, some not, or the PHI
  // itself never being alloca-family-propagated at all per this pass's
  // own deliberate choice not to merge AllocaBase across a PHI's several
  // possibly-different roots) must never be treated as either a heap
  // -tracked or stack-tracked address -- doing so would silently
  // misinterpret one shadow representation as the other. Real, honest,
  // narrow gap (matches this project's own established "diagnosed and
  // left unrewritten" convention): such a PHI's own resulting loads/
  // stores are left completely unprotected, not miscompiled.
  bool isAmbiguousAllocaPhi(Value *Addr, const DenseMap<Value *, Value *> &AB) {
    auto *PN = dyn_cast<PHINode>(Addr);
    if (!PN)
      return false;
    return llvm::any_of(PN->incoming_values(),
                        [&](Use &U) { return AB.count(U.get()) != 0; });
  }

  // Synthesizes a unique, deterministic shadow-table key for "the pointer
  // -typed value currently stored at (ObjectId, Offset) inside a tracked
  // object" -- used only when persisting/recovering the shadow of a
  // pointer stored INTO another tracked object's own field (the
  // linked-list "next" pointer case), where no real machine address
  // exists to key the shadow table by.
  Value *synthKey(IRBuilder<> &B, Value *ObjectId, Value *Offset) {
    Value *OidExt = B.CreateZExt(ObjectId, I64Ty);
    Value *OidShifted = B.CreateShl(OidExt, ConstantInt::get(I64Ty, 24));
    Value *OffMasked = B.CreateAnd(Offset, ConstantInt::get(I64Ty, 0xFFFFFF));
    Value *Combined = B.CreateOr(OidShifted, OffMasked);
    Value *Tagged =
        B.CreateOr(Combined, ConstantInt::get(I64Ty, kSyntheticKeyTag));
    return B.CreateIntToPtr(Tagged, PtrTy);
  }

  bool rewriteSignatures(Module &M);
  void propagateGlobals(Module &M);
  void propagateInFunction(Function &F);
};

//===----------------------------------------------------------------------===//
// Phase A: give every module-defined, non-runtime-helper function with at
// least one pointer parameter a trailing i32 shadow parameter per pointer
// parameter. Every existing call site is rewritten to target the new
// function, with the sentinel placeholder passed for each new shadow
// argument -- Phase B (propagateInFunction) fixes these placeholders up to
// real, computed shadow values once each call site's own containing
// function has been processed. This ordering (all signatures rewritten
// before any body is analyzed) is required so a call to a function defined
// *later* in module iteration order still sees its final, real signature.
//
// Mechanically follows llvm/lib/Transforms/IPO/DeadArgumentElimination.cpp's
// own real, already-proven function-signature-rewrite pattern (read in
// full before writing this -- new FunctionType -> Function::Create -> fix
// up call sites -> splice the body over -> RAUW the old arguments), just
// appending parameters instead of removing them.
//===----------------------------------------------------------------------===//
bool VedaShadowPropagation::rewriteSignatures(Module &M) {
  SmallVector<Function *, 16> Targets;
  for (Function &F : M) {
    if (F.isDeclaration() || isRuntimeHelper(F))
      continue;
    bool HasPtrParam = llvm::any_of(
        F.args(), [](Argument &A) { return A.getType()->isPointerTy(); });
    // Toolchain Milestone 20: a function returning a pointer is now ALSO a
    // rewrite target, even with zero pointer PARAMETERS (e.g. a real
    // `struct node *make_default(void)`-shaped helper) -- broadens this
    // loop's own original pointer-PARAMETER-only condition to close the
    // real, previously-stated "shadow propagation through a callee's own
    // return value ... not yet implemented" gap (file header comment,
    // TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md Test 2).
    bool ReturnsPtr = F.getFunctionType()->getReturnType()->isPointerTy();
    if (HasPtrParam || ReturnsPtr)
      Targets.push_back(&F);
  }

  for (Function *F : Targets) {
    FunctionType *FTy = F->getFunctionType();
    SmallVector<Type *, 8> NewParams(FTy->params());
    SmallVector<unsigned, 8> PtrIdx;
    for (unsigned I = 0, E = FTy->getNumParams(); I != E; ++I)
      if (FTy->getParamType(I)->isPointerTy())
        PtrIdx.push_back(I);
    for (unsigned I = 0, E = PtrIdx.size(); I != E; ++I)
      NewParams.push_back(I32Ty);

    // Toolchain Milestone 20: one trailing return-shadow out-param
    // (pointer-to-i32), appended AFTER every per-pointer-parameter shadow
    // above -- generalizes the veda_malloc_raw out-param convention
    // (Call->getArgOperand(1) in propagateInFunction) to any module
    // -defined function returning a pointer. `HasRetShadow`'s own value is
    // recomputed identically (not cached from the Targets-selection loop
    // above) since it is cheap and keeps this loop self-contained.
    bool HasRetShadow = FTy->getReturnType()->isPointerTy();
    if (HasRetShadow)
      NewParams.push_back(PtrTy);

    FunctionType *NFTy =
        FunctionType::get(FTy->getReturnType(), NewParams, FTy->isVarArg());
    Function *NF =
        Function::Create(NFTy, F->getLinkage(), F->getAddressSpace());
    NF->copyAttributesFrom(F);
    F->getParent()->getFunctionList().insert(F->getIterator(), NF);
    NF->takeName(F);

    // Rewrite direct call sites only (not indirect calls through some
    // other value that merely happens to alias F -- there are none, since
    // we are iterating F's own use list, which for a direct call is
    // exactly the CallInst itself; a real indirect call goes through a
    // function-pointer Value and never appears in F->users() at all,
    // which is exactly the real, stated "indirect calls are not
    // instrumented" scope limit above).
    SmallVector<CallInst *, 8> Calls;
    for (User *U : F->users())
      if (auto *CI = dyn_cast<CallInst>(U); CI && CI->getCalledFunction() == F)
        Calls.push_back(CI);

    for (CallInst *CI : Calls) {
      SmallVector<Value *, 8> Args(CI->args());
      for (unsigned I = 0, E = PtrIdx.size(); I != E; ++I)
        Args.push_back(InvalidOid); // placeholder; fixed up in Phase B
      if (HasRetShadow)
        // Placeholder -- propagateInFunction's own CallInst handling
        // replaces this with a real, lazily-created per-CALLER scratch
        // slot address before the call ever executes (a real Value* is
        // required here now, a null constant, not the same InvalidOid
        // sentinel the SCALAR shadow placeholders above use, since this
        // argument's own type is ptr, not i32).
        Args.push_back(ConstantPointerNull::get(PtrTy));
      IRBuilder<> B(CI);
      CallInst *NewCI = B.CreateCall(NF, Args);
      NewCI->setCallingConv(CI->getCallingConv());
      NewCI->takeName(CI);
      CI->replaceAllUsesWith(NewCI);
      CI->eraseFromParent();
    }

    NF->splice(NF->begin(), F);
    for (auto [OldArg, NewArg] : llvm::zip(F->args(), NF->args())) {
      NewArg.takeName(&OldArg);
      OldArg.replaceAllUsesWith(&NewArg);
    }
    // Name the newly-appended shadow parameters after the pointer
    // parameter they shadow, matching this project's own established
    // naming discipline (readable IR, not auto-numbered %N operands).
    for (unsigned K = 0, E = PtrIdx.size(); K != E; ++K)
      NF->getArg(NewParams.size() - PtrIdx.size() - (HasRetShadow ? 1 : 0) + K)
          ->setName(NF->getArg(PtrIdx[K])->getName() + ".shadow");
    if (HasRetShadow) {
      unsigned RetShadowIdx = NewParams.size() - 1;
      NF->getArg(RetShadowIdx)->setName("ret.shadow.out");
      ReturnShadowParamIndex[NF] = RetShadowIdx;
    }

    PointerParamIndices[NF] = std::move(PtrIdx);
  }

  for (Function *F : Targets)
    F->eraseFromParent();

  return !Targets.empty();
}

//===----------------------------------------------------------------------===//
// Toolchain Milestone 13: Phase B1 -- module-wide GlobalVariable
// recognition and capability-table slot assignment. Runs once, before
// propagateInFunction's per-function loop (mirroring rewriteSignatures's
// own module-wide-first ordering) -- module-wide, not per-function,
// since a GlobalVariable's own uses genuinely span the whole module
// (confirmed by direct compilation this session: the SAME global can be
// referenced from both a veda_compartment-attributed function and an
// ordinary unattributed one in the same module), architecturally unlike
// Phase B0's AllocaInst (inherently local to the one function that emits
// it). See TOOLCHAIN_MILESTONE_13_DESIGN.md Section 1/3 for the full
// real design reasoning behind every decision below.
//===----------------------------------------------------------------------===//
void VedaShadowPropagation::propagateGlobals(Module &M) {
  const DataLayout &DL = M.getDataLayout();

  // Real, linker-provided region-boundary symbols (runtime/veda_rt.ld,
  // this milestone's own addition) -- referenced here purely for their
  // ADDRESS (ptrtoint), the identical convention this project's own
  // runtime code already uses for a raw linker symbol whose "type" is
  // meaningless (runtime/veda_rt.c's own `extern char _end[];`).
  IntegerType *I8Ty = Type::getInt8Ty(*Ctx);
  GlobalVariable *RodataStart =
      cast<GlobalVariable>(M.getOrInsertGlobal(kRodataStartSym, I8Ty));
  GlobalVariable *DataStart =
      cast<GlobalVariable>(M.getOrInsertGlobal(kDataStartSym, I8Ty));

  // Toolchain Milestone 13's own real scope (TOOLCHAIN_MILESTONE_13_DESIGN.md
  // Section 4): only rewrite uses found inside functions that already
  // carry veda_compartment -- a genuinely new policy question Phase B0
  // never faced, since an alloca is inherently local to one function but
  // a global's own users() legitimately span attributed and unattributed
  // functions alike (confirmed by direct compilation this session). A
  // GEP ConstantExpr operand has no "containing function" of its own --
  // only the real Load/Store instruction that ultimately embeds it does
  // -- so its own users() must be checked one level further to find that
  // instruction.
  auto usedByCompartmentFunction = [](GlobalVariable &GV) {
    for (User *U : GV.users()) {
      if (auto *Inst = dyn_cast<Instruction>(U)) {
        if (Inst->getFunction()->hasFnAttribute("veda_compartment"))
          return true;
        continue;
      }
      if (auto *CE = dyn_cast<ConstantExpr>(U)) {
        for (User *CEU : CE->users())
          if (auto *CEInst = dyn_cast<Instruction>(CEU))
            if (CEInst->getFunction()->hasFnAttribute("veda_compartment"))
              return true;
      }
    }
    return false;
  };

  SmallVector<VedaGlobalTableEntry, 8> TableEntries;
  uint64_t NextSlot = 0;
  for (GlobalVariable &GV : M.globals()) {
    if (GV.isDeclaration())
      // Real, empirically-found sizing-safety gate (LLVM-internals track,
      // this milestone's own research): getTypeAllocSize on an
      // incomplete-type extern (e.g. this project's own real
      // `extern char _end[];`, runtime/veda_rt.c) returns 0, not the real
      // cross-TU size -- unsafe to trust. Only globals actually defined
      // in this translation unit are ever given a table slot.
      continue;
    if (GV.getName() == kRodataStartSym || GV.getName() == kRodataEndSym ||
        GV.getName() == kDataStartSym || GV.getName() == kBssEndSym)
      continue; // the region-boundary symbols themselves, never a real
                // user-defined global this pass should ever protect
    if (!usedByCompartmentFunction(GV))
      continue;
    uint64_t Size = DL.getTypeAllocSize(GV.getValueType());
    if (Size == 0)
      continue;

    bool IsRodata = GV.isConstant();
    GlobalVariable *RegionStart = IsRodata ? RodataStart : DataStart;
    Constant *GVAddr = ConstantExpr::getPtrToInt(&GV, I64Ty);
    Constant *RegionStartAddr = ConstantExpr::getPtrToInt(RegionStart, I64Ty);
    // A link-time-resolved symbol-difference constant, not a plain
    // integer -- the real numeric value is not known until the linker
    // places both @GV and the region-start symbol (TOOLCHAIN_MILESTONE_13_
    // DESIGN.md Section 1's own real reasoning for why this must be a
    // Constant, not a compile-time uint64_t).
    Constant *RegionOffset = ConstantExpr::getSub(GVAddr, RegionStartAddr);

    uint64_t Slot = NextSlot++;
    GlobalTableSlotOffset[&GV] = Slot * kVedaCapTableSlotBytes;
    GlobalSize[&GV] = Size;
    TableEntries.push_back({&GV, IsRodata, RegionOffset, Size, Slot});
  }

  if (TableEntries.empty())
    return; // no veda_compartment function in this module touches any
            // global -- nothing to emit, matching this pass's own
            // zero-overhead-when-unused convention elsewhere (e.g.
            // ScratchSlot's own lazy creation).

  // Emit the bootstrap tuple table as ordinary compiler-generated data --
  // a real, checked departure from CHERI's own literal linker-emitted
  // __cap_relocs mechanism (this project's real linker/clang have no
  // such feature, confirmed directly this session -- see
  // TOOLCHAIN_MILESTONE_13_DESIGN.md Section 3). One tightly-packed
  // { region_selector, region_offset, size } i64 triple per entry --
  // table_slot is deliberately OMITTED from the emitted row itself, since
  // it is always exactly the row's own index * kVedaCapTableSlotBytes,
  // recoverable by the bootstrap routine from its own loop counter alone,
  // matching this pass's own established "don't emit a redundant field"
  // discipline.
  StructType *EntryTy =
      StructType::get(*Ctx, {I64Ty, I64Ty, I64Ty}, /*isPacked=*/true);
  SmallVector<Constant *, 8> Rows;
  for (const VedaGlobalTableEntry &E : TableEntries) {
    Constant *RegionSelector =
        ConstantInt::get(I64Ty, E.IsRodata ? 0 : 1);
    Rows.push_back(ConstantStruct::get(
        EntryTy, {RegionSelector, E.RegionOffset,
                 ConstantInt::get(I64Ty, E.Size)}));
  }
  ArrayType *TableArrTy = ArrayType::get(EntryTy, Rows.size());
  Constant *TableInit = ConstantArray::get(TableArrTy, Rows);
  auto *TableGV = new GlobalVariable(
      M, TableArrTy, /*isConstant=*/true, GlobalValue::ExternalLinkage,
      TableInit, "__veda_global_table_meta");
  auto *CountGV = new GlobalVariable(
      M, I64Ty, /*isConstant=*/true, GlobalValue::ExternalLinkage,
      ConstantInt::get(I64Ty, Rows.size()), "__veda_global_table_count");
  (void)TableGV;
  (void)CountGV;

  // Toolchain Milestone 15 (TOOLCHAIN_MILESTONE_13_DESIGN.md's own
  // pre-named "concrete next design step" -- "exactly as many slots as
  // the tuple table has entries, sized by the compiler pass itself, no
  // separate policy needed"): emit the REAL, runtime-populated capability
  // table (`g_veda_global_cap_table`) here too, exactly sized to
  // Rows.size() * kVedaCapTableSlotBytes -- previously a fixed 16-slot
  // (256-byte) upper bound hardcoded in runtime/veda_rt.c, unrelated to
  // any one program's own real global count. Zero-initialized (not a
  // ConstantArray like TableInit above): this array is populated at
  // RUNTIME by veda_mint_global_cap_*_asm's own OCS.C writes, not at
  // compile time -- ConstantAggregateZero is the correct LLVM
  // zero-initializer for a mutable, not-yet-written array.
  ArrayType *CapTableArrTy =
      ArrayType::get(I8Ty, Rows.size() * kVedaCapTableSlotBytes);
  auto *CapTableGV = new GlobalVariable(
      M, CapTableArrTy, /*isConstant=*/false, GlobalValue::ExternalLinkage,
      ConstantAggregateZero::get(CapTableArrTy), "g_veda_global_cap_table");
  (void)CapTableGV;

  // A companion i64 constant carrying the table's own real byte size --
  // mirrors CountGV's own role exactly, but for the hand-written
  // assembly entry point's own ODT-Populate Length field
  // (veda_global_protect_entry.S), which cannot read an LLVM
  // GlobalVariable's byte size directly (no linker-computed
  // symbol-difference is set up for this array, unlike RegionOffset
  // above) -- a real, load-once constant is the simplest correct
  // mechanism, not a new idiom.
  auto *CapTableBytesGV = new GlobalVariable(
      M, I64Ty, /*isConstant=*/true, GlobalValue::ExternalLinkage,
      ConstantInt::get(I64Ty, Rows.size() * kVedaCapTableSlotBytes),
      "__veda_global_cap_table_bytes");
  (void)CapTableBytesGV;
}

//===----------------------------------------------------------------------===//
// Phase B: per-function dataflow propagation over the now-final IR.
//===----------------------------------------------------------------------===//
void VedaShadowPropagation::propagateInFunction(Function &F) {
  if (F.isDeclaration() || isRuntimeHelper(F))
    return;

  DenseMap<Value *, Value *> Shadow;

  // Toolchain Milestone 12: Phase B0 -- recognize every static AllocaInst
  // in a veda_compartment function's entry block, assign each a fixed
  // compile-time byte offset within the SSC-relative locals sub-region,
  // and seed its shadow with that offset -- a compile-time i32 constant,
  // NOT a runtime Object_ID, unlike heap objects. The existing GEP/BitCast
  // propagation below is reused completely unmodified for the shadow
  // value itself; it already only cares that Shadow.lookup(Addr) returns
  // *some* Value*, regardless of whether that value originated from a
  // malloc call's runtime out-param load or (new) this compile-time
  // ConstantInt. AllocaBase/AllocaSize are a SEPARATE, parallel per-value
  // map (keyed identically to Shadow for every tracked alloca-family
  // value): presence in AllocaBase is what actually distinguishes "this
  // shadow means a stack-local region offset" from "this shadow means a
  // heap Object_ID" at Load/Store rewrite time below.
  //
  // Real, empirically-found placement bug (Toolchain Milestone 12, found
  // via a real sail_riscv_sim trace, not assumed): an EARLIER version of
  // this code anchored offsets at the TOP of the region (kVedaSSCRegionLength
  // minus bytes-reserved-so-far), reasoning that Milestone 11's own
  // FixedCSRFIMap-based CSR spills for the OUTERMOST compartment function
  // land at SP_entry-8..SP_entry-104 = 3992..4088 (since SP_entry =
  // kVedaSSCRegionLength = 4096 at compartment entry), so offsets just
  // below 3992 seemed safe. This is true ONLY for the outermost function.
  // Toolchain Milestone 12's own runtime helpers (veda_ocl_stack_d/
  // veda_ocs_stack_d) are THEMSELVES veda_compartment-attributed (see
  // runtime/veda_rt.c's own header comment on those two functions) and get
  // called from inside the outer function's own call graph -- their CSR
  // spills (e.g. their own `ra`) land at THEIR OWN current-SP-relative
  // offset, and by the time such a nested call site is reached, SP has
  // already drifted DOWN from 4096 by whatever real local-frame space the
  // outer function needed for its own ordinary (non-Phase-B0-tracked)
  // allocas -- e.g. the pass's own `%veda.ocl.scratch` output buffer,
  // which forces a real `addi sp,sp,-N` Phase B0 has no visibility into
  // (it runs at the IR level, long before the backend decides real frame
  // sizes). Confirmed via trace: with the old top-anchored scheme, a
  // nested veda_ocs_stack_d call's own `ra`-spill offset (SP-8, where SP
  // had drifted to 0xF70) landed at absolute offset 0xF68 (3944) --
  // exactly inside this function's own `upper[]` allocation window
  // [3928,3960), silently aliasing `upper[2]`'s real data byte with
  // veda_ocs_stack_d's own spilled return address, corrupting `ra` and
  // crashing on return (misaligned-fetch, confirmed via --trace-gpr).
  //
  // Fixed by anchoring allocas at the BOTTOM of the region instead
  // (starting right after kVedaCSRReservedBytes, growing upward) --
  // maximally far from where ANY current-SP-relative CSR spill can land,
  // since SP starts at kVedaSSCRegionLength (4096) and only ever
  // decreases with deeper nesting/larger real frames, never below 0. For
  // this design's own realistic, bounded call depths (a handful of
  // runtime-helper levels, each needing at most a few dozen bytes of real
  // local-frame space), SP drifting anywhere near offset ~168 (this
  // milestone's own actual alloca footprint) is not a realistic risk --
  // an honest, empirically-grounded margin, not a formally proven bound
  // (the SAME class of hand-maintained, documented risk this file's own
  // kVedaCSRReservedBytes/kVedaSSCRegionLength constants already carry).
  DenseMap<Value *, Value *> AllocaBase; // tracked value -> alloca's own
                                         // ptrtoint'd base address
  DenseMap<Value *, Value *> AllocaSize; // tracked value -> alloca's own
                                         // i64 byte size constant
  if (F.hasFnAttribute("veda_compartment")) {
    const DataLayout &DL = F.getParent()->getDataLayout();
    uint64_t ReservedSoFar = (uint64_t)kVedaCSRReservedBytes;
    for (Instruction &I : llvm::make_early_inc_range(F.getEntryBlock())) {
      auto *AI = dyn_cast<AllocaInst>(&I);
      if (!AI)
        continue;
      auto *ArraySizeCI = dyn_cast<ConstantInt>(AI->getArraySize());
      if (!AI->isStaticAlloca() || !ArraySizeCI) {
        // Dynamic-size (VLA) alloca -- explicitly deferred (Toolchain
        // Milestone 12's own stated scope limit): size genuinely isn't a
        // compile-time constant, breaking this design's core
        // simplification. Left completely unrewritten (zero protection,
        // matching Milestone 8/9's own established convention for
        // untracked addresses), not diagnosed as an error.
        continue;
      }
      uint64_t ElemSize = DL.getTypeAllocSize(AI->getAllocatedType());
      uint64_t Size = ElemSize * ArraySizeCI->getZExtValue();
      if (Size == 0)
        continue;
      uint64_t Alignment = AI->getAlign().value();
      uint64_t AbsoluteOffset = alignTo(ReservedSoFar, Alignment);
      ReservedSoFar = AbsoluteOffset + Size;
      if (ReservedSoFar > (uint64_t)kVedaSSCRegionLength) {
        F.getContext().emitError(
            &I, "veda_compartment function's local variables exceed the "
                "SSC region's own capacity (" + Twine(kVedaSSCRegionLength) +
                " bytes) -- Toolchain Milestone 12's real, honestly-stated "
                "capacity limit, not a silent truncation");
        continue;
      }
      Shadow[AI] = ConstantInt::get(I32Ty, AbsoluteOffset);
      // Insert the ptrtoint immediately after AI itself (the same
      // dominance-safe pattern already used throughout this file for GEP/
      // BitCast/etc. below) -- guaranteed to dominate every real use,
      // unlike a single shared builder captured once at the block's own
      // first insertion point (which does not track newly-inserted
      // instructions' own relative order across multiple allocas).
      IRBuilder<> BaseB(AI->getNextNode());
      AllocaBase[AI] = BaseB.CreatePtrToInt(AI, I64Ty, AI->getName() + ".base");
      AllocaSize[AI] = ConstantInt::get(I64Ty, Size);
    }
  }

  // Seed: pointer parameters <-> the shadow parameter Phase A appended for
  // them (same order, appended after all original parameters).
  auto PPI = PointerParamIndices.find(&F);
  if (PPI != PointerParamIndices.end() && !PPI->second.empty()) {
    // Toolchain Milestone 20: F may ALSO have been given a trailing
    // return-shadow out-param (if F itself returns a pointer -- see
    // ReturnShadowParamIndex), appended in NewParams AFTER every
    // per-pointer-parameter shadow. That extra trailing param must be
    // subtracted back out here too, or NumOrig is off by one and this loop
    // seeds Shadow from the WRONG argument (the return-shadow out-param
    // itself, rather than the real per-parameter shadow) for any function
    // that both takes pointer parameters and returns a pointer -- a real
    // bug, found and fixed while implementing this same milestone, before
    // any test exposed it (F.getFunctionType() here is NF's own, already
    // -rewritten type, not the original F's).
    unsigned NumOrig = F.getFunctionType()->getNumParams() -
                       PPI->second.size() -
                       (ReturnShadowParamIndex.count(&F) ? 1 : 0);
    IRBuilder<> EntryB(&*F.getEntryBlock().getFirstInsertionPt());
    for (unsigned K = 0, E = PPI->second.size(); K != E; ++K) {
      Argument *PtrArg = F.getArg(PPI->second[K]);
      Argument *ShadowArg = F.getArg(NumOrig + K);
      Shadow[PtrArg] = ShadowArg;
      attach(EntryB, PtrArg, ShadowArg);
    }
  }

  // Pass 1: pre-create a placeholder shadow PHI for every pointer-typed PHI
  // node up front, before any incoming edges are known -- the real,
  // standard technique for a value-level dataflow analysis over a
  // (possibly cyclic) CFG.
  DenseMap<PHINode *, PHINode *> ShadowPhi;
  for (BasicBlock &BB : F)
    for (Instruction &I : BB) {
      auto *PN = dyn_cast<PHINode>(&I);
      if (!PN)
        break; // PHIs are always grouped at the top of a block
      if (!PN->getType()->isPointerTy())
        continue;
      PHINode *SPN = PHINode::Create(I32Ty, PN->getNumIncomingValues(),
                                     PN->getName() + ".shadow",
                                     PN->getIterator());
      ShadowPhi[PN] = SPN;
      Shadow[PN] = SPN;
    }

  // Pass 2: process every NON-PHI instruction, computing shadow values.
  // Deliberately NOT interleaved with filling in phi incoming edges (an
  // earlier version of this pass tried a single combined top-down pass and
  // a real bug surfaced under test: a loop-carried phi's own back-edge
  // incoming value (e.g. "%next" feeding "%node = phi ... [%next, %loop]")
  // is very often defined LATER in program order than the phi itself
  // within the very same block -- so at the moment the phi would be
  // "resolved" in a single combined pass, that later value's shadow
  // genuinely is not known yet, silently falling back to the sentinel
  // instead of the real value. Splitting into "compute every non-phi
  // shadow value across the whole function first" (this pass, order does
  // not matter -- Pass 1's placeholders already make every phi's OWN
  // shadow referenceable from anywhere) and only THEN "go back and wire up
  // every phi's real incoming edges" (Pass 3, once the full-function
  // Shadow map is complete) is the correct fix, verified against
  // test/loop_phi_cyclic.ll.
  //
  // Milestone 9: blocks are visited in reverse-post-order (not plain
  // iteration order) -- Phase 2's new icmp-vs-null rule (below) can
  // legitimately depend on a shadow value computed by an instruction in a
  // DIFFERENT, dominating block (e.g. a tracked load in one block, an
  // icmp on its result in a successor block); RPO is the real, standard
  // guarantee that every non-back-edge predecessor is processed first
  // (same technique already verified real and available for Milestone 8's
  // own initial design, re-added here now that Phase 2 genuinely needs
  // it -- PHI handling itself stays entirely in Pass 3 regardless, so
  // this does not reintroduce the cyclic-phi bug already found and fixed).
  Value *ScratchSlot = nullptr; // lazily-created per-function OCL.D out-param
  // Toolchain Milestone 20: lazily-created per-function scratch slot for
  // reading back a CALLEE's return-value shadow (see ReturnShadowParamIndex
  // and the CallInst-handling case below) -- deliberately separate from
  // ScratchSlot above (different real purpose: that one holds an OCL.D
  // -loaded raw i64 DATA value; this one holds an i32 Object_ID shadow),
  // even though both follow the identical lazy-single-alloca-per-function
  // reuse pattern.
  Value *ReturnShadowSlot = nullptr;
  ReversePostOrderTraversal<Function *> RPOT(&F);
  for (BasicBlock *BBPtr : RPOT) {
    BasicBlock &BB = *BBPtr;
    for (Instruction &I : llvm::make_early_inc_range(BB)) {
      if (isa<PHINode>(&I))
        continue; // handled in Pass 3, once every other value is known

      if (auto *GEP = dyn_cast<GetElementPtrInst>(&I)) {
        // GEP never changes which object a pointer refers to -- same
        // shadow value, no new instruction needed to represent that
        // (just reuse the existing shadow Value directly), matching real
        // SoftBound's own "GEP propagates base/bound unchanged" rule.
        if (Value *S = Shadow.lookup(GEP->getPointerOperand())) {
          Shadow[GEP] = S;
          // Toolchain Milestone 12: propagate alloca-family provenance
          // forward through GEP unchanged (same rule as the shadow
          // itself -- a GEP never changes which alloca a pointer refers
          // to, only its own root/size do).
          Value *Root = GEP->getPointerOperand();
          if (Value *Base = AllocaBase.lookup(Root)) {
            AllocaBase[GEP] = Base;
            AllocaSize[GEP] = AllocaSize.lookup(Root);
          }
          IRBuilder<> B(GEP->getNextNode());
          attach(B, GEP, S);
        }
        continue;
      }

      if (auto *BC = dyn_cast<BitCastInst>(&I)) {
        if (Value *S = Shadow.lookup(BC->getOperand(0))) {
          Shadow[BC] = S;
          Value *Root = BC->getOperand(0);
          if (Value *Base = AllocaBase.lookup(Root)) {
            AllocaBase[BC] = Base;
            AllocaSize[BC] = AllocaSize.lookup(Root);
          }
          IRBuilder<> B(BC->getNextNode());
          attach(B, BC, S);
        }
        continue;
      }

      if (auto *SI = dyn_cast<StoreInst>(&I)) {
        Value *Addr = SI->getPointerOperand();
        Value *Stored = SI->getValueOperand();
        if (isAmbiguousAllocaPhi(Addr, AllocaBase))
          continue; // real, honest, narrow gap -- see isAmbiguousAllocaPhi
        if (Value *StackBase = AllocaBase.lookup(Addr)) {
          // Toolchain Milestone 12: the store's destination is a tracked
          // STACK-LOCAL (alloca-family) slot -- redirect through OCA+
          // CSetBounds-derived, capability-checked OCS.D against C15,
          // NOT the heap-style OcsFn (which would misinterpret this
          // region-offset shadow as an Object_ID). Same 64-bit-width
          // scope limit as the heap path.
          Type *StoredTy = Stored->getType();
          if (!StoredTy->isPointerTy() && !StoredTy->isIntegerTy(64))
            continue;
          Value *RegionOffset = Shadow.lookup(Addr);
          Value *AllocSize = AllocaSize.lookup(Addr);
          if (!RegionOffset || !AllocSize)
            continue; // defensive -- should always be set together
          IRBuilder<> B(SI);
          Value *AccessOffset =
              B.CreateSub(B.CreatePtrToInt(Addr, I64Ty), StackBase);
          Value *RawVal = StoredTy->isPointerTy()
                              ? B.CreatePtrToInt(Stored, I64Ty)
                              : Stored;
          B.CreateCall(OcsStackFn,
                       {B.CreateZExt(RegionOffset, I64Ty), AccessOffset,
                        AllocSize, RawVal});
          SI->eraseFromParent();
          continue;
        }
        // Toolchain Milestone 13: the store's destination roots at a
        // qualifying GlobalVariable (compile-time offset already assigned
        // by propagateGlobals) -- redirect through OCL.C-loaded,
        // already-exactly-bounded, capability-checked OCS.D. Real,
        // explicit gate on THIS function's own attribute, not merely on
        // whether GV has a slot at all: GlobalTableSlotOffset is
        // populated module-wide for any global touched by AT LEAST ONE
        // veda_compartment function, so an access from a DIFFERENT,
        // unattributed function reaching the SAME global must still be
        // left completely untouched (TOOLCHAIN_MILESTONE_13_DESIGN.md
        // Section 4's own explicit scope boundary -- a genuinely new
        // policy question Phase B0 never faced, since an alloca's own
        // AllocaBase map is inherently already function-scoped).
        if (F.hasFnAttribute("veda_compartment")) {
          if (GlobalVariable *GV = findGlobalRoot(Addr)) {
            auto SlotIt = GlobalTableSlotOffset.find(GV);
            if (SlotIt != GlobalTableSlotOffset.end()) {
              Type *StoredTy = Stored->getType();
              if (!StoredTy->isPointerTy() && !StoredTy->isIntegerTy(64))
                continue; // out of scope width, see file header
              IRBuilder<> B(SI);
              Value *AccessOffset = B.CreateSub(
                  B.CreatePtrToInt(Addr, I64Ty), B.CreatePtrToInt(GV, I64Ty));
              Value *RawVal = StoredTy->isPointerTy()
                                  ? B.CreatePtrToInt(Stored, I64Ty)
                                  : Stored;
              B.CreateCall(OcsGlobalFn,
                           {ConstantInt::get(I64Ty, SlotIt->second),
                            AccessOffset,
                            ConstantInt::get(I64Ty, GlobalSize[GV]), RawVal});
              SI->eraseFromParent();
              continue;
            }
          }
        }
        if (Value *AddrShadow = Shadow.lookup(Addr)) {
          // Milestone 9: the STORE'S OWN DESTINATION is a tracked,
          // object-relative slot -- this is a real dereference of a
          // Veda-Core object, not ordinary memory. Redirect through real
          // OCS.D entirely (see file header: only 64-bit-wide values are
          // handled, matching real hardware's own OCL.D/OCS.D-only width).
          Type *StoredTy = Stored->getType();
          if (!StoredTy->isPointerTy() && !StoredTy->isIntegerTy(64))
            continue; // out of scope width -- left as an ordinary store
          IRBuilder<> B(SI);
          Value *Offset = computeOffset(B, Addr);
          Value *RawVal = StoredTy->isPointerTy()
                              ? B.CreatePtrToInt(Stored, I64Ty)
                              : Stored;
          B.CreateCall(OcsFn, {AddrShadow, Offset, RawVal});
          if (StoredTy->isPointerTy()) {
            // The stored VALUE is itself a tracked pointer (the
            // linked-list "node->next = new_node" case) -- persist its
            // own shadow Object_ID keyed by the synthetic (object,offset)
            // key, since the target slot has no real machine address to
            // key a normal @veda_shadow_store call by.
            Value *ValShadow = Shadow.lookup(Stored);
            Value *Key = synthKey(B, AddrShadow, Offset);
            B.CreateCall(ShadowStoreFn,
                         {Key, ValShadow ? ValShadow : InvalidOid});
          }
          SI->eraseFromParent();
          continue;
        }
        // Address not tracked (ordinary stack/global/non-Veda-Core memory)
        // -- unchanged Milestone 8 behavior: persist the stored pointer
        // VALUE's own shadow, keyed by the real address.
        if (!Stored->getType()->isPointerTy())
          continue;
        Value *S = Shadow.lookup(Stored);
        IRBuilder<> B(SI->getNextNode());
        B.CreateCall(ShadowStoreFn, {Addr, S ? S : InvalidOid});
        continue;
      }

      if (auto *LI = dyn_cast<LoadInst>(&I)) {
        Value *Addr = LI->getPointerOperand();
        if (isAmbiguousAllocaPhi(Addr, AllocaBase))
          continue;
        if (Value *StackBase = AllocaBase.lookup(Addr)) {
          // Toolchain Milestone 12: mirror-image of the store case above.
          Type *LoadTy = LI->getType();
          if (!LoadTy->isPointerTy() && !LoadTy->isIntegerTy(64))
            continue;
          Value *RegionOffset = Shadow.lookup(Addr);
          Value *AllocSize = AllocaSize.lookup(Addr);
          if (!RegionOffset || !AllocSize)
            continue;
          // Real, empirically-found requirement (found via a real
          // sail_riscv_sim trace, not assumed): unlike the heap-object
          // path below (which reuses ScratchSlot, an out-param written by
          // a plain `sd` -- safe there since M9's heap demos never run
          // inside a live compartment), this alloca-family path IS always
          // reached from inside a live veda_compartment call graph. M19's
          // purecap enforcement is a blanket rule (any raw load/store
          // while veda_mode=1 hard-traps, regardless of what real memory
          // it targets or which function performs it -- confirmed by a
          // real PURECAP_VIOLATION trap, tval=0x227, at the out-param
          // write-back `sd` inside veda_ocl_stack_d_scratch_asm), so an
          // out-param scratch-buffer write-back is fundamentally
          // incompatible here -- no function in the call chain can safely
          // perform it, since Phase B0's provenance tracking is purely
          // intraprocedural and never extends across a function
          // boundary to a passed-in pointer argument. Fixed by returning
          // the loaded value DIRECTLY in a0 (OclStackFn's own real
          // signature is `uint64_t(i64,i64,i64)`, not
          // `void(i64,i64,i64,ptr)`) -- no memory access at all, sidestepping
          // this whole class of bug rather than routing around it.
          IRBuilder<> B(LI);
          Value *AccessOffset =
              B.CreateSub(B.CreatePtrToInt(Addr, I64Ty), StackBase);
          Value *RawVal = B.CreateCall(
              OclStackFn,
              {B.CreateZExt(RegionOffset, I64Ty), AccessOffset, AllocSize});
          Value *Result = LoadTy->isPointerTy()
                              ? B.CreateIntToPtr(RawVal, LoadTy)
                              : RawVal;
          LI->replaceAllUsesWith(Result);
          LI->eraseFromParent();
          continue;
        }
        // Toolchain Milestone 13: mirror-image of the store case above --
        // same explicit F-attribute gate for the same real reason.
        if (F.hasFnAttribute("veda_compartment")) {
          if (GlobalVariable *GV = findGlobalRoot(Addr)) {
            auto SlotIt = GlobalTableSlotOffset.find(GV);
            if (SlotIt != GlobalTableSlotOffset.end()) {
              Type *LoadTy = LI->getType();
              if (!LoadTy->isPointerTy() && !LoadTy->isIntegerTy(64))
                continue; // out of scope width, see file header
              IRBuilder<> B(LI);
              Value *AccessOffset = B.CreateSub(
                  B.CreatePtrToInt(Addr, I64Ty), B.CreatePtrToInt(GV, I64Ty));
              Value *RawVal = B.CreateCall(
                  OclGlobalFn, {ConstantInt::get(I64Ty, SlotIt->second),
                               AccessOffset,
                               ConstantInt::get(I64Ty, GlobalSize[GV])});
              Value *Result = LoadTy->isPointerTy()
                                  ? B.CreateIntToPtr(RawVal, LoadTy)
                                  : RawVal;
              LI->replaceAllUsesWith(Result);
              LI->eraseFromParent();
              continue;
            }
          }
        }
        if (Value *AddrShadow = Shadow.lookup(Addr)) {
          // Milestone 9: real dereference of a tracked object -- redirect
          // through OCL.D.
          Type *LoadTy = LI->getType();
          if (!LoadTy->isPointerTy() && !LoadTy->isIntegerTy(64))
            continue; // out of scope width, see above
          IRBuilder<> B(LI);
          Value *Offset = computeOffset(B, Addr);
          if (!ScratchSlot) {
            IRBuilder<> EntryB(&*F.getEntryBlock().getFirstInsertionPt());
            ScratchSlot = EntryB.CreateAlloca(I64Ty, nullptr, "veda.ocl.scratch");
          }
          B.CreateCall(OclFn, {AddrShadow, Offset, ScratchSlot});
          Value *RawVal = B.CreateLoad(I64Ty, ScratchSlot);
          Value *Result = LoadTy->isPointerTy()
                              ? B.CreateIntToPtr(RawVal, LoadTy)
                              : RawVal;
          LI->replaceAllUsesWith(Result);
          if (LoadTy->isPointerTy()) {
            Value *Key = synthKey(B, AddrShadow, Offset);
            Value *LoadedShadow =
                B.CreateCall(ShadowLoadFn, {Key}, LI->getName() + ".shadow");
            Shadow[Result] = LoadedShadow;
            attach(B, Result, LoadedShadow);
          }
          LI->eraseFromParent();
          continue;
        }
        // Address not tracked -- unchanged Milestone 8 behavior.
        if (!LI->getType()->isPointerTy())
          continue;
        IRBuilder<> B(LI->getNextNode());
        Value *S = B.CreateCall(ShadowLoadFn, {Addr}, LI->getName() + ".shadow");
        Shadow[LI] = S;
        attach(B, LI, S);
        continue;
      }

      if (auto *Cmp = dyn_cast<ICmpInst>(&I)) {
        // Milestone 9: a "ptr vs null" comparison against a TRACKED
        // pointer must compare shadow Object_IDs, not raw pointer bit
        // patterns -- see file header for why raw-pointer null comparison
        // is genuinely meaningless under the offset-token representation
        // (every fresh object's own pointer numerically starts at the
        // same kVedaNullBase).
        if (!Cmp->isEquality())
          continue;
        Value *LHS = Cmp->getOperand(0), *RHS = Cmp->getOperand(1);
        bool LHSNull = isa<ConstantPointerNull>(LHS);
        bool RHSNull = isa<ConstantPointerNull>(RHS);
        Value *PtrOperand = nullptr;
        if (LHSNull && !RHSNull)
          PtrOperand = RHS;
        else if (RHSNull && !LHSNull)
          PtrOperand = LHS;
        if (!PtrOperand || !PtrOperand->getType()->isPointerTy())
          continue;
        if (AllocaBase.count(PtrOperand))
          // Toolchain Milestone 12: a stack address is never meaningfully
          // compared to null in real C (no frontend emits `&local ==
          // NULL`) -- skip the rewrite entirely rather than inventing
          // invalid-alloca-shadow null semantics for a case that will
          // not occur.
          continue;
        Value *S = Shadow.lookup(PtrOperand);
        if (!S)
          continue; // untracked pointer -- ordinary null comparison is fine
        IRBuilder<> B(Cmp);
        Value *NewCmp = B.CreateICmp(Cmp->getPredicate(), S, InvalidOid);
        Cmp->replaceAllUsesWith(NewCmp);
        Cmp->eraseFromParent();
        continue;
      }


      if (auto *Call = dyn_cast<CallInst>(&I)) {
        Function *Callee = Call->getCalledFunction();
        if (Callee && Callee->getName() == kMallocRawName) {
          // Recognize the malloc-source pattern:
          //   %p = call ptr @veda_malloc_raw(i64 %size, ptr %oid_slot)
          // The object_id is fetched by the pass's OWN inserted load from
          // the out-param slot (the call's 2nd argument) -- robust
          // regardless of whatever the surrounding C code does with that
          // slot afterward, unlike relying on a sibling instruction the
          // caller may or may not have already emitted.
          Value *OidSlot = Call->getArgOperand(1);
          IRBuilder<> B(Call->getNextNode());
          Value *OidVal = B.CreateLoad(I32Ty, OidSlot, "oid");
          Shadow[Call] = OidVal;
          attach(B, Call, OidVal);
          continue;
        }
        if (!Callee || isRuntimeHelper(*Callee))
          continue; // indirect call, or a runtime primitive -- out of scope
        auto It = PointerParamIndices.find(Callee);
        auto RIt = ReturnShadowParamIndex.find(Callee);
        if (It == PointerParamIndices.end() &&
            RIt == ReturnShadowParamIndex.end())
          continue; // callee has no pointer params and doesn't return a
                    // pointer, or was never rewritten
        bool HasRetShadow = RIt != ReturnShadowParamIndex.end();
        unsigned PtrShadowCount =
            It != PointerParamIndices.end() ? It->second.size() : 0;
        // Both trailing param groups (per-pointer-parameter shadows, then
        // -- always AFTER those -- the single return-shadow out-param, see
        // rewriteSignatures) were appended past the function's original
        // arity; subtracting both back out recovers where the ORIGINAL
        // parameters end and the appended ones begin, regardless of which
        // of the two groups (or both) this particular Callee has.
        unsigned NumOrig = Callee->getFunctionType()->getNumParams() -
                           PtrShadowCount - (HasRetShadow ? 1 : 0);
        if (It != PointerParamIndices.end()) {
          for (unsigned K = 0, E = It->second.size(); K != E; ++K) {
            Value *OrigArg = Call->getArgOperand(It->second[K]);
            Value *S = Shadow.lookup(OrigArg);
            Call->setArgOperand(NumOrig + K, S ? S : InvalidOid);
          }
        }
        if (HasRetShadow) {
          // Toolchain Milestone 20: generalizes the malloc_raw out-param
          // convention above to ordinary module-defined, pointer-returning
          // functions -- one shared, lazily-created scratch slot per
          // CALLING function (mirrors ScratchSlot's own established
          // lazy-per-function-reuse idiom for OCL.D loads elsewhere in
          // this same Pass 2 loop): safe to reuse across multiple call
          // sites within F, since each call's resulting shadow is read
          // back and cached into the Shadow map immediately after that
          // one call, before any later call could overwrite the slot.
          if (!ReturnShadowSlot) {
            IRBuilder<> EntryB(&*F.getEntryBlock().getFirstInsertionPt());
            ReturnShadowSlot =
                EntryB.CreateAlloca(I32Ty, nullptr, "veda.ret.shadow.scratch");
          }
          Call->setArgOperand(RIt->second, ReturnShadowSlot);
          IRBuilder<> B(Call->getNextNode());
          Value *RetShadow = B.CreateLoad(I32Ty, ReturnShadowSlot,
                                          Call->getName() + ".retshadow");
          Shadow[Call] = RetShadow;
          attach(B, Call, RetShadow);
        }
        continue;
      }

      if (auto *RI = dyn_cast<ReturnInst>(&I)) {
        // Toolchain Milestone 20: the write-back half -- if F ITSELF was
        // rewritten with a trailing return-shadow out-param (F returns a
        // pointer type, see rewriteSignatures), store the returned
        // pointer's own known shadow (or InvalidOid, the same "unknown"
        // default used everywhere else in this pass) through that
        // out-param immediately before returning, so the CALLER's own
        // CallInst-handling above has something real to load back.
        auto RIt = ReturnShadowParamIndex.find(&F);
        if (RIt != ReturnShadowParamIndex.end() && RI->getReturnValue() &&
            RI->getReturnValue()->getType()->isPointerTy()) {
          Value *RetVal = RI->getReturnValue();
          Value *S = Shadow.lookup(RetVal);
          IRBuilder<> B(RI);
          B.CreateStore(S ? S : InvalidOid, F.getArg(RIt->second));
        }
        continue;
      }
    }
  }

  // Pass 3: now that every non-phi shadow value in the function is known
  // (including ones defined later in program order than a phi that
  // depends on them via a back edge), go back and wire up each
  // placeholder shadow phi's real incoming edges, and attach a marker for
  // the original phi's own final result.
  for (auto &[PN, SPN] : ShadowPhi) {
    for (unsigned K = 0, E = PN->getNumIncomingValues(); K != E; ++K) {
      Value *IncShadow = Shadow.lookup(PN->getIncomingValue(K));
      SPN->addIncoming(IncShadow ? IncShadow : InvalidOid,
                       PN->getIncomingBlock(K));
    }
    IRBuilder<> B(&*PN->getParent()->getFirstInsertionPt());
    attach(B, PN, SPN);
  }
}

PreservedAnalyses VedaShadowPropagation::run(Module &M,
                                             ModuleAnalysisManager &) {
  Ctx = &M.getContext();
  I32Ty = Type::getInt32Ty(*Ctx);
  I64Ty = Type::getInt64Ty(*Ctx);
  PtrTy = PointerType::getUnqual(*Ctx);
  InvalidOid = ConstantInt::get(I32Ty, kInvalidObjectId);

  ShadowStoreFn = M.getOrInsertFunction(
      kShadowStoreName, FunctionType::get(Type::getVoidTy(*Ctx),
                                          {PtrTy, I32Ty}, false));
  ShadowLoadFn = M.getOrInsertFunction(
      kShadowLoadName, FunctionType::get(I32Ty, {PtrTy}, false));
  ShadowAttachFn = M.getOrInsertFunction(
      kShadowAttachName, FunctionType::get(Type::getVoidTy(*Ctx),
                                           {PtrTy, I32Ty}, false));
  OclFn = M.getOrInsertFunction(
      kOclFnName, FunctionType::get(Type::getVoidTy(*Ctx),
                                    {I32Ty, I64Ty, PtrTy}, false));
  OcsFn = M.getOrInsertFunction(
      kOcsFnName, FunctionType::get(Type::getVoidTy(*Ctx),
                                    {I32Ty, I64Ty, I64Ty}, false));
  // Toolchain Milestone 12: (region_offset, access_offset, size) -> i64,
  // no Object_ID (unlike OclFn/OcsFn above) and no out-param (unlike
  // OclFn) -- the loaded value returns directly in a0, since an out-param
  // write-back is fundamentally incompatible with live purecap
  // enforcement here (see the Load-rewrite call site's own comment).
  OclStackFn = M.getOrInsertFunction(
      kOclStackFnName, FunctionType::get(I64Ty, {I64Ty, I64Ty, I64Ty}, false));
  OcsStackFn = M.getOrInsertFunction(
      kOcsStackFnName, FunctionType::get(Type::getVoidTy(*Ctx),
                                         {I64Ty, I64Ty, I64Ty, I64Ty}, false));
  // Toolchain Milestone 13: (table_slot_offset, access_offset, size) ->
  // i64, no Object_ID -- mirrors OclStackFn/OcsStackFn's own real ABI
  // shape exactly (value returned directly in a0, no out-param;
  // Milestone 12's own finding 3 applies identically here).
  OclGlobalFn = M.getOrInsertFunction(
      kOclGlobalFnName, FunctionType::get(I64Ty, {I64Ty, I64Ty, I64Ty}, false));
  OcsGlobalFn = M.getOrInsertFunction(
      kOcsGlobalFnName, FunctionType::get(Type::getVoidTy(*Ctx),
                                          {I64Ty, I64Ty, I64Ty, I64Ty}, false));

  bool Changed = rewriteSignatures(M);
  propagateGlobals(M);

  SmallVector<Function *, 16> Funcs;
  for (Function &F : M)
    Funcs.push_back(&F);
  for (Function *F : Funcs)
    propagateInFunction(*F);

  if (verifyModule(M, &errs())) {
    errs() << "VedaShadowPropagation: produced an invalid module -- this is "
             "a real pass bug, not expected input malformation.\n";
  }

  return Changed ? PreservedAnalyses::none() : PreservedAnalyses::all();
}

} // namespace

llvm::PassPluginLibraryInfo getVedaShadowPropagationPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "VedaShadowPropagation", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            // Explicit `-passes=veda-shadow-prop` invocation (opt / lit
            // FileCheck tests, Milestone 8's own verification method).
            PB.registerPipelineParsingCallback(
                [](StringRef Name, ModulePassManager &MPM,
                  ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "veda-shadow-prop") {
                    MPM.addPass(VedaShadowPropagation());
                    return true;
                  }
                  return false;
                });
            // Milestone 9: automatic invocation via plain
            // `clang -fpass-plugin=...` with no explicit `-passes=` --
            // registerPipelineStartEPCallback fires unconditionally at
            // the very start of the module pipeline, confirmed (by
            // reading PassBuilderPipelines.cpp's own real
            // buildO0DefaultPipeline, not assumed) to run even at -O0,
            // which this milestone's demo deliberately uses (see
            // TOOLCHAIN_MILESTONE_9_RESULTS.md for why: avoids any
            // UB-based optimizer assumption about the pointer
            // -as-offset-token representation this pass relies on).
            PB.registerPipelineStartEPCallback(
                [](ModulePassManager &MPM, OptimizationLevel) {
                  MPM.addPass(VedaShadowPropagation());
                });
          }};
}

extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return getVedaShadowPropagationPluginInfo();
}
