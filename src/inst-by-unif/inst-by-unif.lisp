(in-package :pvs)

(defstep inst! (&optional (fnums *)
			  subst
			  (where *)
			  copy?
			  (if-match best)
			  complete?
			  (relativize? T))
  (let ((sforms (s-forms (current-goal *ps*)))
	(inst-sforms (gather-seq sforms fnums nil
				 (compose #'essentially-existential? #'formula)))
	(inst-fnums (gather-fnums sforms fnums nil
				  (compose #'essentially-existential? #'formula))))
    (if (null inst-sforms)
	(skip-msg "Could not find an existential-strength formula.")
      (let ((inst-fmlas (mapcar #'formula inst-sforms))
	    (where-fmlas  (remove-if #'(lambda (fmla)
					 (member fmla
						 inst-fmlas
						 :test #'tc-eq))
			    (mapcar #'formula
			      (select-seq sforms where))))
	    (rule (ignore-errors
	                (construct-inst-rule inst-fnums
				             subst
				             inst-fmlas
				             where-fmlas
				             if-match
				             copy?
				             complete?
				             relativize?
				             nil))))
	(if rule rule
	    (skip-msg "No suitable instantiation found")))))
  "Tries to find instantiations for the toplevel, existential strength
   bindings in the sequent formulas specified by FNUMS.
   First, a full case split for the formulas specified by FNUMS and
   WHERE is computed; e.g. a formula in the hypothesis of the form
   FORALL (x: { y: T | P(y)}): Q(x) => R(x) gives rise to two
   sequents in the split corresponding the two parts of the
   implication; if the RELATIVIZE? flag is set then the predicate subtype
   is also taken into account. Then, a set of candidate substitutions is
   generated by unifying complementary pairs in the resulting sequents,
   respectively. If there are several such candidates, the procedure uses
   some supposedly best substitution if flat IF-MATCH is set to BEST.
   For the other choices of the IF-MATCH flag refer to the help text
   of INST?. If the COMPLETE? flag is set then only full instantiations
   of the toplevel bindings are being considered.
   Finally, the VERBOSE? flag causes the strategy to display some additional
   information like the number of sequences in the full case split or the
   score of the selected instantiation.

   CAVEAT: This strategy is included for experimental purposes only
   and its functionality (and speed!) is most likely to change in future
   releases. Thus, proof scripts that are using it are likely to break
   in the future!"
  "Instantiating quantified variables")

;; Splits a set of formulas into a list of arguments of negated
;;   formulas (negative formulas, hypotheses) and a list of
;;   (positive) formulas (conclusions)

(defun construct-inst-rule (fnums initial-subst inst-fmlas where-fmlas
				  if-match copy? complete? relativize? verbose? &optional state)
   (let ((*start-state* (or state
			    *init-dp-state*          ; skip *dp-state*
			    (dp::null-single-cong-state)))
	 (*complete* complete?)
	 (*relativize* relativize?)
	 (*verbose* verbose?))
     (declare (special *start-state*)
	      (special *complete*)
	      (special *relativize*)
	      (special *verbose*))
     (multiple-value-bind (list-of-toplevel-bndngs bodies renamings)
	 (destructure-inst-fmlas inst-fmlas initial-subst)
       (let ((lvars (collect-vars renamings))
	     (all-bndngs (reduce #'append list-of-toplevel-bndngs))
	     (fmlas (union bodies where-fmlas :test #'tc-eq)))
	 (let ((*bound-variables* (append all-bndngs *bound-variables*)))
	   (declare (special *bound-variables*))
	   (if (null lvars)
	       (inst!-rule-top fnums list-of-toplevel-bndngs (list renamings) renamings copy? if-match)
	       (multiple-value-bind (trms new-lvars new-renamings)
		   (herbrandize fmlas lvars renamings 'T)
		 (declare (ignore new-renamings)
			  (ignore new-lvars))
		 (let ((score-substs (dp::gensubsts lvars trms *verbose*)))
		   (if (null score-substs) nil
		       (let ((substs (choose-substs score-substs if-match)))
			 (inst!-rule-top fnums list-of-toplevel-bndngs substs renamings copy? if-match)))))))))))

(defun collect-vars (renamings)
  "Lists all the variables in the range of the substitution"
  (if (null renamings) nil
      (let ((assoc (car renamings)))
	(if (dp::dp-variable-p (cdr assoc))
	    (adjoin (cdr assoc) (collect-vars (cdr renamings)))
	  (collect-vars (cdr renamings))))))
  
(defun destructure-inst-fmlas (fmlas initial-subst &optional list-of-bndngs bodies renamings)
  (assert (listp fmlas))
  (if (null fmlas)
      (values (reverse list-of-bndngs) (reverse bodies) (reverse renamings))
      (multiple-value-bind (bndngs body)
	  (destructure-toplevel-existential (car fmlas))
	(let ((*bound-variables* (append bndngs *bound-variables*)))
	  (declare (special *bound-variables*))
	  (multiple-value-bind (assocs new-initial-subst)
	      (construct-assocs bndngs initial-subst)
	    (destructure-inst-fmlas (cdr fmlas)
				    new-initial-subst
				    (cons bndngs list-of-bndngs)
				    (cons body bodies)
				    (append assocs renamings)))))))

(defun destructure-toplevel-existential (fmla)
  (declare (special *relativize*))
    (cond ((exists-expr? fmla)
	   (let ((fmla1 (relativize-quantifier fmla *relativize*)))
	     (values (bindings fmla1) (expression fmla1))))
	  ((and (negation? fmla)
		(forall-expr? (args1 fmla)))
	   (let ((fmla1 (relativize-quantifier (args1 fmla) *relativize*)))
	     (values (bindings fmla1) (make!-negation (expression fmla1)))))
	  (t (values nil fmla))))

(defun construct-assocs (bndngs subst &optional assocs)
  "Construct a list of associations (x . trm) where x is the translation
   of a binding and trm is either a new variable or a term constructed from
   the initial substitution."
  (if (null bndngs)
      (values (reverse assocs) subst)
      (let* ((bndng (car bndngs))
	     (x1    (top-translate-to-dc bndng)))
	(multiple-value-bind (trm1 subst1)
	    (cond ((< (length subst) 2)
		   (values (mk-new-var bndng) nil))
		  ((string= (symbol-name (id bndng)) (first subst))
		   (let ((trm (ignore-errors
				(pc-typecheck (pc-parse (second subst) 'expr)))))
		     (values (or (and trm
				      (top-translate-to-dc trm))
				 (mk-new-var bndng))
			     (nthcdr 2 subst))))
		  (t (values (mk-new-var bndng) subst)))
	  (construct-assocs (cdr bndngs) subst1 (acons x1 trm1 assocs))))))
			
(defun choose-substs (score-substs if-match)
  (if (or (eq if-match :best) (eq if-match 'best))
      (list (choose-best-subst score-substs))
      (mapcar #'(lambda (score-subst)
		  (dp::substitution-of score-subst))
	score-substs)))

(defun choose-best-subst (score-substs &optional (best-score 0) best-subst)
  (declare (special *verbose*))
  (cond ((null score-substs)
	 (when *verbose*
	   (format t "~%Top score: ~a" best-score))
	 best-subst)
	(t (let ((current-score  (dp::score-of (car score-substs)))
		 (current-subst (dp::substitution-of (car score-substs))))
	     (multiple-value-bind (new-score new-subst)
		 (if (or (and (> (length current-subst)
				 (length best-subst))
			      (>= current-score best-score))
		         (> current-score best-score))
		     (values current-score current-subst)
		   (values best-score best-subst))
	       (choose-best-subst (cdr score-substs) new-score new-subst))))))
    
;; Construct a PVS rule from instantiations of the form;
;; e.g.  ((1 (e1 e2 e3)) (-4 (f1 f2))) indicates 3 instantiations
;; for the top-level bindings of the sequence formula numbered 1
;;  and two instantiations for the sequent formula -4.

(defun inst!-rule-top (fnums list-of-bndngs substs renamings copy? if-match)
  (let ((*renamings* renamings)
	(*substs* substs)
	(*copy* copy?)
	(*if-match* (if (or (eq if-match :best) (eq if-match 'best)) nil if-match)))
    (declare (special *renamings*)
	     (special *substs*)
	     (special *copy*)
	     (special *if-match*))
    (inst!-rule* fnums list-of-bndngs)))

(defun inst!-rule* (fnums list-of-bndngs)
  (if (null fnums)
      '(skip)
      `(then* ,(inst!-rule (car fnums) (car list-of-bndngs))
	      ,(inst!-rule* (cdr fnums) (cdr list-of-bndngs)))))

(defun inst!-rule (fnum bndngs)
  (declare (special *copy*) (special *if-match*))
  (let* ((insts (construct-insts bndngs))
	 (insts1 (if (and
		         (not (eq *if-match* 'all))
		         (listp insts)          ; patch
			 (= (length insts) 1)
			 (listp (first insts))
			 (= (length (first insts)) 1)
			 (listp (first (first insts))))
		    (first insts)
		  insts)))
    (display-substitution fnum bndngs insts1)
    (if (null insts1) '(skip)
	(make-inst?-rule fnum insts1 *copy* *if-match*))))
         ; e.g. (make-inst?-rule -2 '(((x)) ((a 1))) nil 'all)
         ; but: (make-inst?-rule -1 '((t1 b(t1))) NIL NIL)

(defun construct-insts (bndngs)
  (declare (special *substs*))
  (cond ((= (length *substs*) 0)
         (let ((inst (construct-inst bndngs nil)))
	   (and inst
		(list (list inst)))))
	((= (length *substs*) 1)
	 (let ((inst (construct-inst bndngs (first *substs*))))
	   (and inst (list (list inst)))))
	(t (construct-insts-for-subst *substs* bndngs))))

(defun construct-insts-for-subst (substs bndngs &optional acc)
  (if (null substs) (nreverse acc)
      (let* ((inst   (construct-inst bndngs (car substs)))
	     (newacc (if inst (cons (list inst) acc) acc)))
	(construct-insts-for-subst (cdr substs) bndngs newacc))))

(defun construct-inst (bndngs subst)
  (declare (special *complete*))
  (let ((inst (construct-inst* bndngs subst)))
    (if (empty-inst? inst) '()
	(if *complete*
	    (if (complete-inst? inst) inst '())
	    inst))))

(defun empty-inst? (inst)
  (every #'(lambda (trm)
	     (and (stringp trm) (string= "_" trm)))
	 inst))

(defun construct-inst* (bndngs subst)
  (declare (special *renamings*))
  (loop for bndng in bndngs
	collect (let ((pair (assoc (top-translate-to-dc bndng) *renamings*)))
		  (if (not pair) "_"
		      (let ((trm (cdr pair)))
			(cond ((null (dp::vars-of trm)) ; from initial substitution
			       (translate-from-dc trm))
			      ((dp::dp-variable-p trm)  ; from computes substitution
			       (let ((pair (assoc trm subst)))
				 (or (and pair
					  (or (translate-from-dc (cdr pair))
					       "_"))
				     "_")))
			      (t "_")))))))

(defun complete-inst? (inst)
  (not (incomplete-inst? inst)))

(defmethod incomplete-inst? ((inst null))
  nil)

(defmethod incomplete-inst? ((inst cons))
  (or (and (stringp (car inst))
           (string= "_" (car inst)))
      (incomplete-inst? (cdr inst))))

(defun display-substitution (fnum bndngs trms)
  (unless (null trms)
    (format-if "~%Substitution:")
    (format-if "~%   ~a: ~{~a~^, ~} --> ~{~a~^, ~}" fnum bndngs trms)))


