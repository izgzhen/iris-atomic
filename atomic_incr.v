From iris.program_logic Require Export weakestpre wsat.
From iris.heap_lang Require Export lang proofmode notation.
From iris_atomic Require Import atomic.
From iris.proofmode Require Import tactics.
From iris.prelude Require Import coPset.

Section incr.
  Context `{!heapG Σ} (N : namespace).

  Definition incr: val :=
    rec: "incr" "l" :=
       let: "oldv" := !"l" in
       if: CAS "l" "oldv" ("oldv" + #1)
         then "oldv" (* return old value if success *)
         else "incr" "l".

  Global Opaque incr.

  (* TODO: Can we have a more WP-style definition and avoid the equality? *)
  Definition incr_triple (l: loc) :=
    atomic_triple _ (fun (v: Z) => l ↦ #v)%I
                    (fun v ret => ret = #v ★ l ↦ #(v + 1))%I
                    (nclose heapN)
                    ⊤
                    (incr #l).

  Lemma incr_atomic_spec: ∀ (l: loc), heapN ⊥ N → heap_ctx ⊢ incr_triple l.
  Proof.
    iIntros (l HN) "#?".
    rewrite /incr_triple.
    rewrite /atomic_triple.
    iIntros (P Q) "#Hvs".
    iLöb as "IH".
    iIntros "!# HP".
    wp_rec.
    wp_bind (! _)%E.
    iVs ("Hvs" with "HP") as (x) "[Hl [Hvs' _]]".
    wp_load.
    iVs ("Hvs'" with "Hl") as "HP".
    iVsIntro. wp_let. wp_bind (CAS _ _ _). wp_op.
    iVs ("Hvs" with "HP") as (x') "[Hl Hvs']".
    destruct (decide (x = x')).
    - subst.
      iDestruct "Hvs'" as "[_ Hvs']".
      iSpecialize ("Hvs'" $! #x').
      wp_cas_suc.
      iVs ("Hvs'" with "[Hl]") as "HQ"; first by iFrame.
      iVsIntro. wp_if. iVsIntro. by iExists x'.
    - iDestruct "Hvs'" as "[Hvs' _]".
      wp_cas_fail.
      iVs ("Hvs'" with "[Hl]") as "HP"; first by iFrame.
      iVsIntro. wp_if. by iApply "IH".
  Qed.
End incr.

From iris.heap_lang.lib Require Import par.

Section user.
  Context `{!heapG Σ, !spawnG Σ} (N : namespace).

  Definition incr_2 : val :=
    λ: "x",
       let: "l" := ref "x" in
       incr "l" || incr "l";;
       !"l".

  (* prove that incr is safe w.r.t. data race. TODO: prove a stronger post-condition *)
  Lemma incr_2_safe:
    ∀ (x: Z), heapN ⊥ N -> heap_ctx ⊢ WP incr_2 #x {{ _, True }}.
  Proof.
    iIntros (x HN) "#Hh".
    rewrite /incr_2.
    wp_let.
    wp_alloc l as "Hl".
    iVs (inv_alloc N _ (∃x':Z, l ↦ #x')%I with "[Hl]") as "#?"; first eauto.
    wp_let.
    wp_bind (_ || _)%E.
    iApply (wp_par (λ _, True%I) (λ _, True%I)).
    iFrame "Hh".
    (* prove worker triple *)
    iDestruct (incr_atomic_spec N l with "Hh") as "Hincr"=>//.
    rewrite /incr_triple /atomic_triple.
    iSpecialize ("Hincr"  $! True%I (fun _ _ => True%I) with "[]").
    - iIntros "!# _".
      (* open the invariant *)
      iInv N as (x') ">Hl'" "Hclose".
      (* mask magic *)
      iVs (pvs_intro_mask' (⊤ ∖ nclose N) heapN) as "Hvs"; first set_solver.
      iVsIntro. iExists x'. iFrame "Hl'". iSplit.
      + (* provide a way to rollback *)
        iIntros "Hl'".
        iVs "Hvs". iVs ("Hclose" with "[Hl']"); eauto.
      + (* provide a way to commit *)
        iIntros (v) "[Heq Hl']".
        iVs "Hvs". iVs ("Hclose" with "[Hl']"); eauto.
    - iDestruct "Hincr" as "#HIncr".
      iSplitL; [|iSplitL];
        try (iApply wp_wand_r; iSplitL; [by iApply "HIncr"|auto]).
      iIntros (v1 v2) "_ !>".
      wp_seq. iInv N as (x') ">Hl" "Hclose".
      wp_load. iApply "Hclose". eauto.
  Qed.
End user.