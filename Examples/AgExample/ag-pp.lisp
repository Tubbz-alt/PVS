(defmethod pp* :around ((ex application))
  (let ((operator (get-pp-operator* (operator ex)))
	(args (get-pp-argument* (operator ex) (list (argument ex)))))
    (cond ((and (name-expr? operator)
		(eq (id operator) '|meaningF|)
		(eq (id (module-instance operator)) '|FODL_semantic|)
		(= (length args) 2))
	   (call-next-method (mk-application (car args) (cadr args))))
	  ((and (name-expr? operator)
		(eq (id operator) '|left|)
		(eq (id (module-instance operator)) '|union_adt|)
		(= (length args) 2)
		(application? (car args)))
	   ;; left(m(M)(inl(F)))(w) ==> F(M)(w)
	   (let ((m-op (get-pp-operator* (operator (car args))))
		 (m-args (get-pp-argument* (operator (car args))
					   (list (argument (car args))))))
	     (if (and (name-expr? m-op)
		      (eq (id m-op) '|m|)
		      (eq (id (module-instance m-op)) '|FODL_semantic|)
		      (= (length m-args) 2)
		      (application? (cadr m-args))
		      (name-expr? (operator (cadr m-args)))
		      (eq (id (operator (cadr m-args))) '|inl|)
		      (eq (id (module-instance (operator (cadr m-args))))
			  '|union_adt|))
		 (call-next-method (mk-application
				       (mk-application (argument (cadr m-args))
					 (car m-args))
				     (cadr args)))
		 (call-next-method))))
	  ((and (name-expr? operator)
		(eq (id operator) '|right|)
		(eq (id (module-instance operator)) '|union_adt|)
		(= (length args) 2)
		(application? (car args)))
	   ;; right(m(M)(inr(P)))(w) ==> P(M)(w)
	   (let ((m-op (get-pp-operator* (operator (car args))))
		 (m-args (get-pp-argument* (operator (car args))
					   (list (argument (car args))))))
	     (if (and (name-expr? m-op)
		      (eq (id m-op) '|m|)
		      (eq (id (module-instance m-op)) '|FODL_semantic|)
		      (= (length m-args) 2)
		      (application? (cadr m-args))
		      (name-expr? (operator (cadr m-args)))
		      (eq (id (operator (cadr m-args))) '|inr|)
		      (eq (id (module-instance (operator (cadr m-args))))
			  '|union_adt|))
		 (call-next-method (mk-application
				       (mk-application (argument (cadr m-args))
					 (car m-args))
				     (cadr args)))
		 (call-next-method))))
	  (t (call-next-method)))))

(defmethod pp* :around ((ex type-name))
	   (if (eq (id ex) 'World_)
	       (write (id ex))
	       (call-next-method)))
