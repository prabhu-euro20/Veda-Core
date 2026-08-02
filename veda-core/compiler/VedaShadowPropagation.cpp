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
//     caller is not yet implemented -- only argument-direction passing.
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
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace {

constexpr char kMallocRawName[] = "veda_malloc_raw";
constexpr char kShadowStoreName[] = "veda_shadow_store";
constexpr char kShadowLoadName[] = "veda_shadow_load";
constexpr char kShadowAttachName[] = "veda_shadow_attach";
constexpr char kOclFnName[] = "veda_rt_ocl_d";
constexpr char kOcsFnName[] = "veda_rt_ocs_d";
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

  // Per (already-rewritten) function: original parameter indices that are
  // pointer-typed, in the same order their shadow params were appended.
  // Populated by rewriteSignatures, consumed by propagateInFunction (both
  // for seeding a callee's own entry-point ShadowMap, and for fixing up
  // shadow arguments at every call site targeting that function).
  DenseMap<Function *, SmallVector<unsigned, 8>> PointerParamIndices;

  static bool isRuntimeHelper(const Function &F) {
    StringRef N = F.getName();
    return N == kMallocRawName || N == kShadowStoreName ||
          N == kShadowLoadName || N == kShadowAttachName ||
          N == kOclFnName || N == kOcsFnName;
  }

  void attach(IRBuilder<> &B, Value *Ptr, Value *Shadow) {
    B.CreateCall(ShadowAttachFn, {Ptr, Shadow});
  }

  // Byte offset of a tracked pointer within its own object -- see the
  // pointer-as-offset-token discussion in the file header.
  Value *computeOffset(IRBuilder<> &B, Value *Addr) {
    Value *AsInt = B.CreatePtrToInt(Addr, I64Ty);
    return B.CreateSub(AsInt, ConstantInt::get(I64Ty, kVedaNullBase));
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
    if (llvm::any_of(F.args(),
                     [](Argument &A) { return A.getType()->isPointerTy(); }))
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
      NF->getArg(NewParams.size() - PtrIdx.size() + K)
          ->setName(NF->getArg(PtrIdx[K])->getName() + ".shadow");

    PointerParamIndices[NF] = std::move(PtrIdx);
  }

  for (Function *F : Targets)
    F->eraseFromParent();

  return !Targets.empty();
}

//===----------------------------------------------------------------------===//
// Phase B: per-function dataflow propagation over the now-final IR.
//===----------------------------------------------------------------------===//
void VedaShadowPropagation::propagateInFunction(Function &F) {
  if (F.isDeclaration() || isRuntimeHelper(F))
    return;

  DenseMap<Value *, Value *> Shadow;

  // Seed: pointer parameters <-> the shadow parameter Phase A appended for
  // them (same order, appended after all original parameters).
  auto PPI = PointerParamIndices.find(&F);
  if (PPI != PointerParamIndices.end()) {
    unsigned NumOrig = F.getFunctionType()->getNumParams() - PPI->second.size();
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
          IRBuilder<> B(GEP->getNextNode());
          attach(B, GEP, S);
        }
        continue;
      }

      if (auto *BC = dyn_cast<BitCastInst>(&I)) {
        if (Value *S = Shadow.lookup(BC->getOperand(0))) {
          Shadow[BC] = S;
          IRBuilder<> B(BC->getNextNode());
          attach(B, BC, S);
        }
        continue;
      }

      if (auto *SI = dyn_cast<StoreInst>(&I)) {
        Value *Addr = SI->getPointerOperand();
        Value *Stored = SI->getValueOperand();
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
        if (It == PointerParamIndices.end())
          continue; // callee has no pointer params, or was never rewritten
        unsigned NumOrig =
            Callee->getFunctionType()->getNumParams() - It->second.size();
        for (unsigned K = 0, E = It->second.size(); K != E; ++K) {
          Value *OrigArg = Call->getArgOperand(It->second[K]);
          Value *S = Shadow.lookup(OrigArg);
          Call->setArgOperand(NumOrig + K, S ? S : InvalidOid);
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

  bool Changed = rewriteSignatures(M);

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
