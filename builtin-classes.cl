(in-package :python)

;;; Built-in classes and their methods


;; There is a special method __new__ that accepts as first argument
;; classes instead of instances. Need to special-case them in
;; __call__, therefore keep track of them in a hash-table.

(defparameter *__new__-methods* (make-hash-table :test #'eq))

(defmethod register-as-__new__method ((f function))
  (setf (gethash f *__new__-methods*) t))

(defmethod is-a-__new__-method ((f function))
  (gethash f *__new__-methods*))


;; Class-specific non-magic methods, like the `clear' methods of
;; dicts, and the `append' method of lists, are stored in a hashtable,
;; where the key is the method name as a symbol, and the value is an
;; alist where the class is the key, and the method for that class and
;; its type are in the cons that is the value.

(defparameter *builtin-class-attr/meths* (make-hash-table :test #'eq))

(defmethod register-bi-class-attr/meth ((class class) (meth-name symbol) (func function) (type symbol))
  "Puts the method in the hash table. TYPE is either :ATTR or :METH."
  (assert (member type '(:attr :meth)))
  (let* ((alist (gethash meth-name *builtin-class-attr/meths*))
	 (kons  (cons class (cons func type)))
	 (assval (assoc class alist)))
    (when assval
      (warn "builtin-class-methods already had a func for method ~A of class ~A"
	    meth-name class))
    (if alist
	(push kons alist)
      (setf (gethash meth-name *builtin-class-attr/meths*) (list kons)))))

(defmethod lookup-bi-class-attr/meth ((class class) (meth-name symbol))
  "Returns METHOD, TYPE. Both are NIL if not found."
  (let ((val (cdr (assoc class (gethash meth-name *builtin-class-attr/meths*)))))
    (values (car val) (cdr val))))

(defmacro def-class-specific-methods (class data)
  `(progn ,@(loop for (attname func kind) in data
		collect `(register-bi-class-method (find-class ',class) ',attname ,func ,kind))))



;; TODO:
;;  - __mro__ attribute of classes
;;  - need for __eq__ when __cmp__ is already defined?

;; These macros ease GF method definition

(defmacro def-unary-meths (py-type cl-type py->cl-form meths)
  `(progn ,@(loop for (methname result) in meths
		collect `(progn (defmethod ,methname ((x ,py-type))
				  (let ((x ,py->cl-form))
				    ,result))
				(defmethod ,methname ((x ,cl-type))
				  ,result)))))


(defmacro def-binary-meths (py-type cl-type py->cl-form-x py->cl-form-y data)
  `(progn ,@(loop for (methname result) in data
		collect `(progn (defmethod ,methname ((x ,py-type) (y ,py-type))
				  (let ((x ,py->cl-form-x)
					(y ,py->cl-form-y))
				    ,result))
				(defmethod ,methname ((x ,py-type) (y ,cl-type))
				  (let ((x ,py->cl-form-x))
				    ,result))
				(defmethod ,methname ((x ,cl-type) (y ,py-type))
				  (let ((y ,py->cl-form-y))
				    ,result))
				(defmethod ,methname ((x ,cl-type) (y ,cl-type))
				  ,result)))))




;;; A few methods shared by all standard objects:
;;; 
;;; __class__, __delattr__, __doc__, __getattribute__, __hash__,
;;; __init__, __new__, __reduce__, __reduce_ex__, __repr__,
;;; __setattr__, __str__
;;; 
;;; Using metaclasses, classes can be created that might not have
;;; these methods.

(defgeneric __class__ (x)
  (:documentation "The class of X. X must be a python-object designator."))

(defmethod __class__ ((x integer))       (find-class 'py-int))
(defmethod __class__ ((x real))          (find-class 'py-float))
(defmethod __class__ ((x complex))       (find-class 'py-complex))
(defmethod __class__ ((x string))        (find-class 'py-string))
(defmethod __class__ ((x user-defined-class)) (find-class 'python-type)) ;; TODO metaclass
(defmethod __class__ ((x function))      (find-class 'python-type)) ;; XXX doesn't show function name
(defmethod __class__ ((x python-object)) (class-of x)) ;; XXX check

;; PYTHON-OBJECT is both an instance and a subclass of PYTHON-TYPE.
(defmethod __class__ ((x (eql (find-class 'python-object)))) (find-class 'python-type))

;; PYTHON-TYPE is it's own type.
(defmethod __class__ ((x (eql (find-class 'python-type)))) x)


(defgeneric __delattr__ (x attr) (:documentation "Delete attribute named ATTR of X"))
(defmethod  __delattr__ (x attr)  (internal-del-attribute x attr))
(register-bi-class-attr/meth (find-class 'python-object) '__delattr__ #'__delattr__ :meth)

(defgeneric __doc__ (x) (:documentation "documentation"))
(defmethod  __doc__ (x) (multiple-value-bind (val found)
			    (internal-get-attribute x '__doc__)
			  (if found
			      val
			    *None*)))
(register-bi-class-attr/meth (find-class 'python-object) '__doc__ #'__doc__ :attr)

(defgeneric __getattribute__ (x attr))
(defmethod  __getattribute__ (x attr)
  (or (internal-get-attribute x attr)
      (py-raise 'AttributeError "object ~A no attribute ~A" x attr)))
(register-bi-class-attr/meth (find-class 'python-object) '__getattribute__ #'__getattribute__ :meth)

(defgeneric __hash__ (x))
(defmethod  __hash__ (x) (pyb:id x)) ;; hash defaults to id

(defgeneric __init__ (x &rest arguments))
(defmethod  __init__ (x &rest arguments)
  (declare (ignore arguments))
  *None*)

(defgeneric __new__ (cls &rest arguments))
(defmethod __new__ (cls &rest arguments)
  (declare (ignore arguments))
  (make-instance cls))

#+(or) ;; don't for now...
(progn (defgeneric __reduce__ ---)"; "helper for pickle"
       (defmethod ---))a

#+(or) ;; don't for now...
(progn (defgeneric __reduce_eq__ ---)"; "helper for pickle"
       (defmethod ---))


;; Regarding string representation of Python objects:
;;    __str__       is a representation targeted to humans
;;    __repr__      if possible,  eval(__repr__(x)) should be equal to x
;; 
;; To reduce duplication:
;;    print-object  falls back to writing __str__
;;    __str__       falls back to returning __repr__
;;    __repr__      returns by default the print-unreadable-object representation

(defmethod print-object ((x python-object) stream)
  ;; it's not a good idea to fall back to __str__, because it could give
  ;; infinite loops when debugging __str__ methods, for example.
  (print-unreadable-object (x stream :identity t :type t)))

(defmethod __str__ (x) 
  ;; This method is not only for X of type python-object, but also for
  ;; regular numbers, for example.
  (__repr__ x))

(defmethod __repr__ (x)
  ;; Also for all X, not just Python objects.
  (with-output-to-string (s)
    (print-unreadable-object (x s :identity t :type t))))

(defgeneric __setattr__ (x attr val))
(defmethod  __setattr__ (x attr val)
  (internal-set-attribute x attr val))

#+(or) ;; XXX
(def-class-specific-methods
    python-type
    ((__new__  #'py-type-__new__  :meth)
     (__init__ #'py-type-__init__ :meth)))
;; etc...


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Some default methods (XXX or just regular functions?)

;; XXX todo...

(defun py-type-__new__ (cls &rest options)
  (declare (ignore options))
  (make-instance cls))

(defmethod __init__((x python-object) &optional pos-args kw-args)
  (declare (ignore pos-args kw-args)))
			    
(def-class-specific-methods
    python-type
    ((__new__  #'py-type-__new__  :meth)
     (__init__ #'py-type-__init__ :meth)))

(register-as-__new__method #'py-type-__new__)
 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Some special singleton classes: None, Ellipsis, NotImplemented

(defmacro def-static-singleton-classes (data)
  `(progn
     ,@(loop for (class-name class-doc object object-doc object-repr object-hash) in data
	   collect 
	     (progn (assert (typep object-hash 'fixnum))
		    `(progn (defclass ,class-name (builtin-object) ()
				      (:documentation ,class-doc)
				      (:metaclass builtin-class))
			    (mop:finalize-inheritance (find-class ',class-name))
			    
			    (defvar ,object (make-instance ',class-name) ,object-doc)
			    
			    ;; CPython disallows creating instances of these.
			    
			    (defmethod make-instance
				((c (eql (find-class ',class-name))) &rest initargs)
			      (declare (ignore initargs))
			      #1=(py-raise 'TypeError
					   "Cannot create '~A' instances" ',class-name))
			    
			    (defmethod make-instance
				((c (eql ',class-name)) &rest initargs)
			      (declare (ignore initargs))
			      #1#)
			    
			    (defmethod __repr__ ((c ,class-name))
			      ,object-repr)
			    
			    (defmethod __hash__ ((c ,class-name))
			      ,object-hash))))))

(def-static-singleton-classes
    ;; They don't have any special methods, other than those of all objects
    ((py-none "The NoneType class"
	      *None* "The Python value/object `None', similar to CL's `nil'"
	      "None" 239888)
     
     (py-ellipsis "The EllipsisType class"
		  *Ellipsis* "Represent `...' in things like `x[1,...,1]'"
		  "Ellipsis" 177117)

     (py-notimplemented "To signal unsupported arguments for binary operation"
			*NotImplemented* "An operation is not implemented"
			"NotImplemented" -99221188)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Number
;; 
;; The Python number classes are subtypes of this class. CPython has
;; no corresponding class.

(defclass py-number (builtin-instance)
  ((val :type number :initarg :val :initform 0))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-number))


(deftype py-number-designator ()
  `(or number py-number))

(defun py-number-designator-p (x)
  "Returns NUM-DES-P, LISP-NUM"
  (typecase x
    (number (values t x))
    (py-number (values t (slot-value x 'val)))
    (t nil)))


(defmethod make-py-number ((val number))
  "Make a PY-NUMBER instance for Lisp number VAL"
  (etypecase val
    (integer (make-int val))
    (real (make-float (coerce val 'double-float)))
    (complex (make-complex val))))

  
(defmethod __hash__ ((x py-number))
  (__hash__ (slot-value x 'val)))

(def-unary-meths 
    py-number number (slot-value x 'val)
    (
     ;; CPython prints *sys-neg-maxint* <= x <= *sys-pos-maxint* as X,
     ;; outside that range as XL:  3 vs 3L. Let's not bother.
     (__repr__     (format nil "~A" x))
     
     (__nonzero__  (lisp-val->py-bool (/= x 0)))
     (__neg__      (- x))
     (__pos__      x)
     (__abs__      (abs x))
     (__complex__  (make-complex x))))

(def-binary-meths py-number number (slot-value x 'val) (slot-value y 'val)

		  ;; comparison -> t/nil	
		  ((__eq__  (= x y))
		   (__ne__  (/= x y))
		   
		   ;; arithmethic -> lisp number
		   (__add__      (+ x y))
		   (__radd__     (+ x y))
		   (__sub__      (- x y))
		   (__mul__      (* x y))
		   (__rmul__     (* x y))
		   (__truediv__  (/ x y))
		   (__rtruediv__ (/ y x))
		   (__rsub__     (- y x))))

;; Power
;; 
;; pow(a,b)   <=> a**b
;; pow(a,b,c) <=> (a**b) % c
;; 
;; As CPython has deprecated the use of modulo and division on complex
;; numbers and Lisp doesn't support it, it's not supported here
;; either.
;; 
;; However, pow(x,y) with x,y complex numbers is no problem.

(defmethod __pow__ (x y &optional m)
  (macrolet ((check-real (var)
	       `(typecase ,var
		  (real)
		  (py-real (setf ,var (slot-value ,var 'val)))
		  (t (py-raise 'TypeError "Unsupported operands for power (got: ~A ~A ~A)"
			       x y m))))
	     (check-number (var)
	       `(typecase ,var
		  (number)
		  (py-number (setf ,var (slot-value ,var 'val)))
		  (t (py-raise 'TypeError "Unsupported operands for power (got: ~A ~A ~A)"
			       x y m)))))
    (if m
	(progn (check-real x)
	       (check-real y)
	       (check-real m)
	       (mod (expt x y) m))
      (progn (check-number x)
	     (check-number y)
	     (expt x y)))))


;; Built-in function pow() will not call __rpow__ with 3 arguments,
;; but user code might.

(defmethod __rpow__ (x y &optional m)
  (__pow__ y x m))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Real
;; 
;; Corresponds to Lisp type `real'. CPython has no corresponding class.

(defclass py-real (py-number)
  ((val :type real :initform 0))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-real))

(deftype py-real-designator ()
  `(or real py-real))

(defun py-real-designator-p (x)
  (typecase x
    (real (values t x))
    (py-real (values t (slot-value x 'val)))
    (t nil)))

(def-unary-meths
    py-real real (slot-value x 'val)
    ((__int__     (make-int (truncate x))) ;; CPython: returns a long int for X large enough
     (__long__    (make-int (truncate x))) ;; CPython: returns long int
     (__float__   (make-float x))))

(def-binary-meths
    py-real real (slot-value x 'val) (slot-value y 'val)
    
    ;; comparison -> t/nil	
    ;; These are not defined on complexes, only on reals.
    ((__lt__  (< x y))
     (__gt__  (> x y))
     (__le__  (<= x y))
     (__ge__  (>= x y))
     (__mod__ (mod x y))
     (__rmod__ (mod y x))
     
     ;; As FLOOR takes REAL arguments, not COMPLEX, some operations
     ;; that Python allows (although they are deprecated) on complexes
     ;; are not allowed here.
    
     (__cmp__ (cond ((< x y) -1)
		    ((> x y)  1)
		    ((= x y)  0)))
     (__div__       (floor x y))
     (__rdiv__      (__div__ y x))
     (__floordiv__  (floor x y))
     (__rfloordiv__ (__floordiv__ y x))
     (__divmod__    (make-tuple-from-list (multiple-value-list (floor x y))))
     (__rdivmod__   (__divmod__ y x))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Complex (corresponds to Lisp type `complex')

(defclass py-complex (py-real)
  ((val :type complex :initarg :val :initform #C(0 0)))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-complex))

(defun make-complex (&optional (val #C(0 0)))
  (make-instance 'py-complex :val (coerce val 'complex)))


(def-unary-meths
    py-complex complex (slot-value x 'val)
    ((__hash__ (if (= (imagpart x) 0)
		   (__hash__ (realpart x))
		 (sxhash x)))
     (__repr__ (if (= (complex-imag x) 0)
		   (__repr__ (complex-real x))
		 (format nil "~(A + ~Aj)" (realpart x) (imagpart x))))
     (complex-real (realpart x))
     (complex-imag (imagpart x))
     (complex-conjugate (conjugate x))))



(def-class-specific-methods
    py-complex
    ((real      #'complex-real      :attr)
     (imag      #'complex-imag      :attr)
     (conjugate #'complex-conjugate :attr)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Float (corresponding to Lisp type `double-float')

(defclass py-float (py-real)
  ((val :type double-float :initform 0d0))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-float))

(defun make-float (&optional (val 0d0))
  (make-instance 'py-float :val val))

(defmethod __hash__ ((x float))
  ;; general `float', not `double-float' as type!
  (multiple-value-bind (int-part float-part)
      (truncate x)
    (if (= float-part 0)
	(__hash__ int-part) ;; hash(3.0) must equal hash(3)
      (sxhash x)))) ;; hash(3.xxx) doesn't matter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Integer (corresponding to Lisp type `integer')

;; these are the min-max Python `normal' integer values; outside this
;; range it becomes a `long'. Not used yet: we don't separate the two
;; integer types anywhere, as CPython doesn't do that often, either.
#+(or)(defconstant *sys-pos-maxint* 2147483647)
#+(or)(defconstant *sys-neg-maxint* -2147483648)
    
(defclass py-int (py-real)
  ((val :type integer :initarg :val :initform 0))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-int))

(defun make-int (&optional (val 0))
  (make-instance 'py-int :val val))

(deftype py-int-designator ()
  `(or integer py-int))

(defun py-int-designator-p (x)
  "Return DESIGNATOR-P, LISP-VAL where LISP-VAL only makes sense if it's ~
   indeed a designator"
  (cond ((integerp x)      (values t x))
	((typep x 'py-int) (values t (slot-value x 'val)))
	(t nil)))

(defun py-int-designator-val (x)
  "Return the Lisp int value of a Python integer designator."
  (typecase x
    (integer x)
    (py-int  (slot-value x 'val))
    (t       (py-raise "Integer expected (got: ~S)" x))))

(def-binary-meths
    py-int integer (slot-value x 'val) (slot-value y 'val)
    ;; bit operations -> lisp integer
    ((__and__ (logand x y))
     (__xor__ (logxor x y))
     (__or__  (logior x y))

     ;; ASH accepts both positive and negative second argument, Python only positive.
     (__lshift__ (if (>= y 0)
		     (ash x y)
		   (py-raise 'ValueError "Negative shift count")))
     (__rlshift__ (__lshift__ y x))
     (__rshift__ (if (>= y 0)
		     (ash x (- y))
		   (py-raise 'ValueError "Negative shift count")))
     (__rrshift__ (__rshift__ y x))
     
     ))

(defmethod mod-to-fixnum ((x integer))
  "Return result of MODding i with most-positive-fixnum (which is ~@
   always a fixnum)"
  ;; important property for use in hashes: 3 remains 3; -3 remains -3.
  (let ((x (if (>= x 0) 
	       (mod x (+ 1 most-positive-fixnum))
	     (mod x (- most-negative-fixnum 1)))))
    (assert (typep x 'fixnum))
    x))


(def-unary-meths
    py-int integer (slot-value x 'val)
    ((__invert__  (lognot x))
     (__hash__    (mod-to-fixnum x)) ;; hash(3) == 3; hash(-3) == -3
      
     ;; don't worry about conversion issues - assume CL takes care of them.
     (__complex__ (coerce x 'complex))
     (__int__     (make-int (truncate x)))
     (__long__    (make-int (truncate x)))
     (__float__   (coerce x 'double-float))
     
     ;; string representations
     (__oct__  (format nil "0~O" x))
     (__hex__  (format nil "0x~X" x))))
     

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Bool (derived from Integer)
;; 
;; In Python, booleans are a type of their own: a subclass of
;; `int'. The only members of the `bool' type are `True' and
;; `False'. In numeric contexts they have integer values 1 and 0,
;; respectively.
;; 
;; Some predicate functions return boolean values. They are printed as
;; `True' and `False', not as numbers.

(defclass py-bool (py-int)
  ((val :initform 0 :initarg :val :type bit))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-bool))

(defvar *True* (make-instance 'py-bool :val 1))
(defvar *False* (make-instance 'py-bool :val 0))

(defmethod make-instance ((c py-bool) &rest initargs &key val)
  (if val *True* *False*))

(defun lisp-val->py-bool (&optional val)
  "Make a BOOL (True of False) for given Lisp VAL."
  (check-type val (not python-object) "Lisp value, not a Python value")
  (if val *True* *False*))

(defun py-bool-p (x)
  (typep x 'py-bool))

(defun py-bool-designator-p (x)
  "Returns DESIGNATOR-P, LISP-VALUE (t/nil)"
  (cond ((typep x '(integer 0 1)) (values t (= x 1)))
	((typep x 'py-int) (let ((val (slot-value x 'val)))
			     (cond ((= val 1) (values t t))
				   ((= val 0) (values t nil))
				   (t nil))))
	(t nil)))

(defmethod __repr__ ((x py-bool))
  (if (eq x *True*) "True" "False"))


(defun py-val->lisp-bool (x)
  "VAL is either a Python value or one of the Lisp values T, NIL. ~@
   Returns a generalized Lisp boolean."
  (cond
   ;; T/NIL, True/False/None
   ((member x (load-time-value (list t *True*)) :test 'eq) t)
   ((member x (load-time-value (list nil *False* *None*)) :test 'eq) nil)
   
   ((numberp x) (/= x 0))
   ((stringp x) (not (string= x "")))

   (t (py-lisp-bool-1 x))))

(defun py-lisp-bool-1 (x)
  "Determine truth value of X, by trying the __nonzero__ and __len__ methods. ~@
   Returns a generalized Lisp boolean."
  
  (multiple-value-bind (val found)
      (call-attribute-via-class x '__nonzero__)
    
    (if found 
	(py-val->lisp-bool val)
  
      (multiple-value-bind (val found)
	  (call-attribute-via-class x '__len__)
	(if found 
	    (/= 0 (py-int-designator-val val))
	  ;; If a class defined neither __nonzero__ nor __len__, all
	  ;; instances are considered `True'.
	  t)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Dictionary

(defun safe-py-hash (x)
  "ACL requires hash value to be fixnum: make sure it is."
  (assert (python-object-designator-p x) ()
      "Attempt to put a non-Python value in a Python dict: ~A" x)
  (let ((hash-value (__hash__ x)))
    (assert (typep hash-value 'fixnum) () "Hash code should be fixnum! (~A ~A)"
	    x hash-value)
    hash-value))

(defclass py-dict (builtin-instance)
  ;; TODO: if there are only a very few items in the dict, represent
  ;; it as an alist or something similarly compact.
  ((hash-table :initform (make-hash-table :test '__eq__  :hash-function 'safe-py-hash)))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-dict))

(defun make-dict (&optional data)
  ;; data: alist '((key1 . val1)(key2 . val2)...)
  (let ((d (make-instance 'py-dict)))
    (when data
      (let ((ht (slot-value d 'hash-table)))
	(loop for (k . v) in data
	    do (setf (gethash k ht) v))))
    d))

(defmethod dict->alist ((x py-dict))
  ;; for internal use (`apply' in builtin-funcs.cl)
  (let ((res ()))
    (maphash (lambda (k v) (push (cons k v) res))
	     (slot-value x 'hash-table))
    res))

#+(or) ;; todo
(defmethod __new__ ((x py-dict)))

(defmethod __cmp__ ((x py-dict) (y py-dict))
  (when (eq x y)
    (return-from __cmp__ 0))
  
  (let* ((hx (slot-value x 'hash-table))
	 (hy (slot-value y 'hash-table))
	 (hcx (hash-table-count hx))
	 (hcy (hash-table-count hy)))
    
    (cond ((< hcx hcy) (return-from __cmp__ -1))
	  ((> hcx hcy) (return-from __cmp__ 1)))
    
    (maphash (lambda (key val-x)
	       (multiple-value-bind (val-y found)
		   (gethash key hy)
		 (if found
		     (let ((res (pyb:cmp val-x val-y)))
		       (cond ((= 0 res)) ; cont.
			     ((< 0 res) (return-from __cmp__ -1))
			     ((> 0 res) (return-from __cmp__ 1))))
		   (return-from __cmp__ 1))))
	     hx))
  0)
    
  

(defmethod __eq__ ((x py-dict) (y py-dict))
  "Returns T or NIL."
  (= (__cmp__ x y) 0))

(defmethod __getitem__ ((d py-dict) key)
  (multiple-value-bind (val found)
      (gethash key (slot-value d 'hash-table))
    (if found
	val
      (py-raise 'KeyError "No such key: ~A" (__str__ key)))))

(defmethod __setitem__ ((d py-dict) key val)
  (setf (gethash key (slot-value d 'hash-table) d) val))

(defmethod __delitem__ ((d py-dict) key)
  (remhash key (slot-value d 'hash-table)))
    
		 
;;; willem __add__ etc(?)

(defmethod __repr__ ((d py-dict))
  (with-output-to-string (s)
    (format s "{")
    (pprint-logical-block (s nil)
      (maphash (lambda (k v)
		 (format s "~A: ~A, ~_"
			 (__repr__ k) (__repr__ v)))
	       (slot-value d 'hash-table)))
    (format s "}")))

(defmethod __len__ ((d py-dict))
  (hash-table-count (slot-value d 'hash-table)))

(defmethod __nonzero__ ((d py-dict))
  (lisp-val->py-bool (/= 0 (hash-table-count (slot-value d 'hash-table)))))

;;;; Dict-specific methods, in alphabetic order

(defmethod dict-clear ((d py-dict))
  "Clear all items"
  (clrhash (slot-value d 'hash-table))
  (values))

(defmethod dict-copy ((d py-dict))
  "Create and return copy of dict. Keys and values themselves are shared, ~@
   but the underlying hash-table is different."
  (let* ((new (make-dict))
	 (new-ht (slot-value new 'hash-table)))
    (maphash (lambda (k v)
	       (setf (gethash k new-ht) v))
	     (slot-value d 'hash-table))
    new))

(defmethod dict-fromkeys (seq &optional (val *None*))
  (let* ((d (make-dict))
	(ht (slot-value d 'hash-table)))
    (py-iterate (key seq)
		(setf (gethash key ht) val))
    d))
    
(defmethod dict-get ((d py-dict) key &optional (defval *None*))
  "Lookup KEY and return its val, otherwise return DEFVAL"
  (multiple-value-bind (val found-p)
      (gethash key (slot-value d 'hash-table))
    (if found-p
	val
      defval)))

(defmethod dict-has-key ((d py-dict) key)
  "Predicate"
  (multiple-value-bind (val found-p)
      (gethash key (slot-value d 'hash-table))
    (declare (ignore val))
    (lisp-val->py-bool found-p)))

(defmethod dict-items ((d py-dict))
  "Return list of (k,v) tuples"
  (let* ((h (slot-value d 'hash-table))
	 (res ()))
    (maphash (lambda (k v) (push (make-tuple k v) res))
	     h)
    (make-py-list-from-list res)))

(defmethod dict-iter-items ((d py-dict))
  "Return iterator that successively returns all (k,v) pairs as tuple"
  (let ((res (with-hash-table-iterator (next-f (slot-value d 'hash-table))
	       (make-iterator-from-function
		(lambda () 
		  (multiple-value-bind (ret key val) 
		      (next-f)
		    (when ret
		      (make-tuple key val))))))))
    res))

(defmethod dict-iter-keys ((d py-dict))
  "Return iterator that successively returns all keys"
  (let ((res (with-hash-table-iterator (next-f (slot-value d 'hash-table))
	       (make-iterator-from-function
		(lambda () 
		  (multiple-value-bind (ret key val) 
		      (next-f)
		    (declare (ignore val))
		    (when ret
		      key)))))))
    res))

(defmethod dict-iter-values ((d py-dict))
  "Return iterator that successively returns all values"
  (let ((res (with-hash-table-iterator (next-f (slot-value d 'hash-table))
	       (make-iterator-from-function
		(lambda () 
		  (multiple-value-bind (ret key val) 
		      (next-f)
		    (declare (ignore key))
		    (when ret
		      val)))))))
    res))

(defmethod dict-keys ((d py-dict))
  "List of all keys"
  (let* ((h (slot-value d 'hash-table))
	 (res ()))
    (maphash (lambda (k v)
	       (declare (ignore v))
	       (push k res))
	     h)
    (make-py-list-from-list res)))

(defmethod dict-pop ((d py-dict) key &optional (default nil default-p))
  "Remove KEY from D, returning its value. If KEY absent, DEFAULT ~
   is returned or KeyError is raised."
  (with-slots (hash-table) d
    (multiple-value-bind (val found)
	(gethash key hash-table)
      (cond (found (remhash key hash-table)
		   val)
	    (default-p default)
	    (t (py-raise 'KeyError "No key ~A in dict" key))))))

(defmethod dict-popitem ((d py-dict))
  (with-slots (hash-table) d
    (with-hash-table-iterator (iter hash-table)
      (multiple-value-bind (entry? key val)
	  (iter)
	(if entry?
	    (progn
	      (remhash key hash-table)
	      (make-tuple key val))
	  (py-raise 'KeyError "popitem: dictionary is empty"))))))

(defmethod dict-setdefault ((d py-dict) key &optional (defval *None*))
  "Lookup KEY and return its val;
   If KEY doesn't exist, add it and set its val to DEFVAL, then return DEFVAL"
  (multiple-value-bind (val found-p)
      (gethash key (slot-value d 'hash-table))
    (if found-p
	val
      (setf (gethash key (slot-value d 'hash-table)) defval))))

(defmethod dict-values ((d py-dict))
  "List of all values"
  (let* ((h (slot-value d 'hash-table))
	 (res ()))
    (maphash (lambda (k v)
	       (declare (ignore k))
	       (push v res))
	     h)
    (make-py-list-from-list res)))

(def-class-specific-methods
    py-dict
    ((clear      #'dict-clear       :meth)
     (copy       #'dict-copy        :meth)
     (fromkeys   #'dict-fromkeys    :meth)
     (get        #'dict-get         :meth)
     (has_key    #'dict-has-key     :meth)
     (items      #'dict-items       :meth)
     (iteritems  #'dict-iter-items  :meth)
     (iterkeys   #'dict-iter-keys   :meth)
     (itervalues #'dict-iter-values :meth)
     (keys       #'dict-keys        :meth)
     (pop        #'dict-pop         :meth)
     (popitem    #'dict-popitem     :meth)
     (setdefault #'dict-setdefault  :meth)
     (values     #'dict-values      :meth)))
     

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Namespace
;; 
;; The methods and attributes of a class, and the lexical scope inside
;; a function, are represented by namespace objects. A namespace
;; behaves like a py-dict.
;; 
;; Compared to dics, namespaces have extra atrtibutes `name' (for
;; debugging, mostly) and `enclosing-ns' (referring to the namespace
;; in which this namespace is enclosed: for classes defined at
;; top-level, this is the module namespace).
;; 
;; When a key doesn't exist, no KeyError is raised (as py-dict does);
;; instead, (nil nil) are returned as values.
;; 
;; (This class might correlate to CPython's Dictproxy, not sure to
;; what degree. Dictproxies don't allow manipulation by the user
;; directly, so d.__getitem__ and d.__setitem__ don't work, although
;; d.items() does.)

(defclass namespace (py-dict)
  ((name :initarg :name :type string)
   (enclosing-ns :initarg :inside :initform nil)
   (hash-table :initform (make-hash-table :test 'eq)))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'namespace))

(defun make-namespace (&key (inside nil) (name nil) (builtins nil))
  "Make a new namespace.
   BUILTINS indicates whether attribute `__builtins__ should ~
     be created and pointed to the namespace with built-in functions
     `<__builtin__ module>.__dict__', available as *__builtin__-module-namespace*.
   INSIDE gives the enclosing scope(s)."
  (let ((ns (make-instance 'namespace :name name :inside inside)))
    (declare (special *__builtin__-module-namespace*))
    (when builtins
      (namespace-bind ns '__builtins__ *__builtin__-module-namespace*))
    ns))

(defmethod namespace-bind ((x namespace) var val)
  (ensure-py-type var attribute-name "Invalid attribute name: ~A")
  (setf (gethash var (slot-value x 'hash-table)) val))

(defmethod namespace-lookup ((x namespace) var)
  "Recursive lookup. Returns two values:  VAL, FOUND-P"
  (ensure-py-type var attribute-name "Invalid attribute name: ~A")
  (let ((res (gethash var (slot-value x 'hash-table))))
    (cond (res
	   (values res t))
	  ((slot-value x 'enclosing-ns)
	   (namespace-lookup (slot-value x 'enclosing-ns) var))
	  (t
	   nil))))

(defmethod namespace-delete ((x namespace) var)
  "Delete the attribute."
  ;; todo: when in an enclosing namespace
  (ensure-py-type var attribute-name "Invalid attribute name: ~A")
  (let ((res (remhash var (slot-value x 'hash-table))))
    (unless res
      (py-raise 'NameError
		"No variable with name ~A" var))))

(defmethod namespace-copy ((x namespace))
  (with-slots (name enclosing-ns hash-table) x
    (let* ((x-copy (make-namespace :inside enclosing-ns
				   :name name))
	   (ht-copy (slot-value x-copy 'hash-table)))
      (clrhash ht-copy)
      (maphash (lambda (k v) (setf (gethash k ht-copy) v))
	       hash-table)
      x-copy)))

(defmethod __getitem__ ((x namespace) key)
  (gethash key (slot-value x 'hash-table)))

(defmethod __repr__ ((x namespace))
  (with-output-to-string (stream)
    (pprint-logical-block (stream nil)
      (format stream "{")
      (maphash (lambda (k v) (format stream "~A: ~A,~_ " (__repr__ k) (__repr__ v)))
	       (slot-value x 'hash-table)))
    (format stream "}")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Function
;; 
;; There are two types of Python functions:
;; 
;; BUILTIN-FUNCTION represents the functions present in de __builtin__
;; module (implemented as Lisp functions)
;; 
;; USER-DEFINED-FUNCTION is used for representing all functions
;; defined while running Python.

(defclass python-function (builtin-instance)
  ((ast             :initarg :ast   
		    :documentation "AST of the function code")
   (params          :initarg :params
		    :documentation "Formal parameters, e.g. '((a b) ((c . 3)(d . 4)) args kwargs)")
   (call-rewriter   :initarg :call-rewriter
		    :documentation "Function that normalizes actual arguments")
   (namespace       :initarg :namespace
	            :type namespace
   	            :documentation "The namespace in which the function code is ~
                                    executed (the lexical scope -- this is not ~
                                    func.__dict__)"))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'python-function))


;; Lambda

(defclass py-lambda-function (python-function)
  ()
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-lambda-function))

(defun make-lambda-function (&rest options)
  (apply #'make-instance 'py-lambda-function options))

(defmethod __repr__ ((x py-lambda-function))
  (with-output-to-string (s)
    (print-unreadable-object (x s :type t :identity t))))


;; Regular function

(defclass user-defined-function (python-function)
  ((name :initarg :name :type string))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'user-defined-function))

(defmethod __repr__ ((x user-defined-function))
  (with-output-to-string (s)
    (print-unreadable-object (x s :type t :identity t)
      (format s "~A" (slot-value x 'name)))))

(defun make-user-defined-function (&rest options &key namespace &allow-other-keys)
  "Make a python function"
  (check-type namespace namespace)
  (apply #'make-instance 'user-defined-function options))

#+(or) ;; unused
(defun python-function-p (f)
  "Predicate: is F a python function?"
  (typep f 'user-defined-function))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Function returning a generator

;;;XX should subclass from function

(defclass python-function-returning-generator (builtin-instance)
  ((call-rewriter :initarg :call-rewriter)
   (generator-creator :initarg :generator-creator))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'python-function-returning-generator))

(defun make-python-function-returning-generator (params ast)
  (make-instance 'python-function-returning-generator
    :call-rewriter (apply #'make-call-rewriter params)
    :generator-creator (eval (create-generator-function ast))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Module

(defclass py-module (builtin-instance)
  ((name :initarg :name :type string)
   (namespace :initarg :namespace :type namespace))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-module))

(defun make-module (&rest options)
  (apply #'make-instance 'py-module options))

(defmethod __repr__ ((x py-module))
  (with-output-to-string (stream)
    (print-unreadable-object (x stream :type t)
      (with-slots (name namespace) x
	(let ((file (namespace-lookup namespace '__file__))
	      (name (namespace-lookup namespace '__name__)))
	  (format stream "~A" (or name "?"))
	  (when file
	    (format stream "from file ~A" file)))))))

(defmethod module-dict ((x py-module))
  (slot-value x 'namespace))

(defmethod namespace-lookup ((x py-module) var)
  (namespace-lookup (slot-value x 'namespace) var))

(def-class-specific-methods
    py-module
    ((__dict__ #'module-dict :attr)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Methods: they come in `bound' and `unbound' flavors
;;
;; An UNBOUND METHOD is a method that is looked up via the class,
;; while a BOUND-METHOD is the result of looking up a class method via
;; an instance. For example:
;;
;;   class C:
;;      def meth(self, ...): ...
;;
;;   C.meth  -> is an unbound method
;;   x = C()
;;   x.meth  -> is a bound method
;;
;; Python attributes of both bound and unbound methods:
;;  `im_class' : the class attribute (here: C)
;;
;; Extra Python attributes for bound methods:
;;  `im_self'  : the instance (here: x)
;;  `im_func'  : the function object (meth)

(defclass py-method (builtin-instance) ()
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-method))

;;;; Unbound

(defclass py-unbound-method (py-method)
  ((class :initarg :class
	  :documentation "The class from which the method is taken.")
   (func :initarg :func :type python-function
	 :documentation "The method itself (of type PYTHON-FUNCTION)."))
  (:documentation "A method from a Python class (NOT bound to ~
                   a class instance).")
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-unbound-method))

(defun make-unbound-method (&rest options)
  (apply #'make-instance 'py-unbound-method options))

(defun unbound-method-p (m)
  (typep m 'py-unbound-method))

(defmethod __repr__ ((x py-unbound-method))
  (with-output-to-string (stream)
    (print-unreadable-object (x stream :identity nil :type t)
      (with-slots (class func) x
	(format stream "~_:class ~S ~_:func ~S" class func)))))


;;;; Bound

(defclass py-bound-method (py-method)
  ((class :initarg :class
	  :documentation "The class from which the method is taken.")
   (func :initarg :func :type python-function
	 :documentation "The method itself (of type PYTHON-FUNCTION).")
   (self :initarg :self
	 :documentation "The instance to which the method is bound."))
  (:documentation "A method from a Python class, bound to a class instance.")
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-bound-method))

;; Make bound method given attributes, or given an unbound method
;; (that will be destructively changed).

(defun convert-unbound-to-bound-method (unbound-method self)
  (check-type unbound-method py-unbound-method)
  (change-class unbound-method 'py-bound-method)
  (setf (slot-value unbound-method 'self) self)
  unbound-method)

(defun make-bound-method (&key self class func)
  (when class
    (check-type class class))
  (when (and self class)
    (check-type self class))
  (make-instance 'py-bound-method
    :self self :class (or class (class-of self)) :func func))

(defun bound-method-p (m)
  (typep m 'py-bound-method))

(defmethod __repr__ ((x py-bound-method))
  (with-output-to-string (stream)
    (print-unreadable-object (x stream :identity nil :type t)
      (with-slots (class func self) x
	(format stream ":class ~S ~_:func ~S ~_:self ~S"
		class func self)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; List
;; 
;; For now, implemented internally as a List consed list. Perhaps an
;; adjustable vector is more efficient.

(defclass py-list (builtin-instance)
  ((list :type list :initarg :list))
  (:documentation "The List type")
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-list))

(defun make-py-list (&rest lst)
  "Make a Python list from the given CL list"
  (make-py-list-from-list lst))


(defun make-py-list-from-list (lst)
  (check-type lst list "A regular Lisp list")
  ;; XXX for now
  (loop for x in lst
      unless (python-object-designator-p x)
      do (warn "Non-python object:  ~A  encountered in MAKE-PY-LIST" x)
	 (return))
  (make-instance 'py-list :list lst))
  

;;;; magic methods

(defmethod __add__ ((x py-list) (y py-list))
  "structure is shared"
  (make-py-list-from-list
   (append (slot-value x 'list) (slot-value y 'list))))

;; CPython lists: no __radd__

(defmethod __cmp__ ((x py-list) (y py-list))
  (__cmp-list__ (slot-value x 'list) (slot-value y 'list)))

(defmethod __cmp-list__ (x y)
  "For tuples and lists: compare the underlying lists. If all elements ~@
   eq, longest wins, otherwise they are eq."
  (do ((x2 x (cdr x2))
       (y2 y (cdr y2)))
      ((not (and x2 y2))
       (cond ((and (null x2) (null y2)) 0)
	     (x2 1) ;; x longer = larger
	     (y2 -1))) ;; y longer = larger
    (let ((res (__cmp__ (car x2) (car y2))))
      (cond ((= res 0)) ;; cont.
	    ((< res 0) (return-from __cmp-list__ -1))
	    ((> res 0) (return-from __cmp-list__ 1))))))

(defmethod __contains__ ((x py-list) item)
  (if (some (lambda (y) (__eq__ item y))
	    (slot-value x 'list))
      *True*
    *False*))

(defmethod __delitem__ ((x py-list) item)
  (typecase item
    (py-int-designator (list-delitem-integer x item))
    (py-slice (list-delitem-slice x item))
    (t (py-raise 'TypeError
		 "List indices must be integers (got: ~A)" item))))

(defun list-delitem-integer (x index)
  (ensure-py-type index integer "internal error: ~A (list-delitem-integer)")
  (let* ((list (slot-value x 'list))
	 (len (length list)))
    (when (< index 0)
      (incf index len))
    (when (or (< index 0)
	      (> index (1- len)))
      (py-raise 'IndexError
		"List index out of range (got: ~A, len: ~A)"
		index len))
    
    (if (= index 0)
	(setf (slot-value x 'list) (cdr list))
      (let ((n-1 (nthcdr (1- index) list))
	    (n+1 (nthcdr (1+ index) list)))
	(setf (cdr n-1) n+1))))
  x)


(defun list-delitem-slice (x slice)
  (declare (ignore x slice))
  ;; XXX needs work
  #+(or)(let* ((list (slot-value x 'list))
	       (len (length list))
	       (destructuring-bind (start stop step)
		   (tuple->lisp-list (indices slice len))
      
		 (when (< start 0)
		   (setf start 0))
		 (when (>= stop len)
		   (setf stop (1- len)))
		 (when (< stop start) ;; = is ok
		   (return-from list-delitem-slice x))
      
		 (if (= start stop)
		     ;; insert slice in what is now empty
		     (((let ((n (nthcdr (
					 ))))))))))))

(defmethod __getitem__ ((x py-list) item)
  (let ((list (slot-value x 'list)))
    (typecase item
      (py-int-designator (extract-list-item-by-index list item))
      (py-slice          (make-py-list-from-list (extract-list-slice list item)))
      (t                 (py-raise 'TypeError
				   "List indices must be integers (got: ~A)" item)))))
  
(defun list-getitem-integer (list index)
  (ensure-py-type index integer
		  "internal error: ~A (list-getitem-integer)")
  (let ((len (length list)))
    (when (< index 0)
      (incf index len))
    (when (or (< index 0)
	      (> index (1- len)))
      (py-raise 'IndexError
		"List index out of range (got: ~A, len: ~A)"
		index len))
    (car (nthcdr index list))))

(defmethod __hash__ ((x py-list))
  (py-raise 'TypeError "List objects are unhashable"))

(defmethod __iter__ ((x py-list))
  (let ((list-copy (copy-list (slot-value x 'list)))) ;; copy-tree ?!
    (make-iterator-from-function
     (lambda ()
       (pop list-copy)))))

(defmethod __len__ ((x py-list))
  (length (slot-value x 'list)))

(defmethod __mul__ ((x py-list) (n integer))
  "structure is copied n times"
  ;; n <= 0 => empty list
  (make-py-list-from-list (loop for i from 1 to n
			      append (slot-value x 'list))))

(defmethod __rmul__ ((x py-list) (n integer)) 
  (__mul__ x n))

(defmethod __nonzero__ ((x py-list))
  (lisp-val->py-bool (/= 0 (length (slot-value x 'list)))))

(defmethod __repr__ ((x py-list))
  (with-output-to-string (s)
    (format s "[~{~A~^, ~}]" (mapcar #'__repr__ (slot-value x 'list)))))


(defmethod __setitem__ ((x py-list) item new-item)
  (typecase item
    (py-int-designator (list-setitem-integer x item new-item))
    (py-slice (list-setitem-slice x item new-item))
    (t (py-raise 'TypeError
		 "List indices must be integers (got: ~A)" item))))
	     
(defun list-setitem-integer (x index new-item)  
  (ensure-py-type index integer "List indices must be integers (got: ~A)")
  (let* ((list (slot-value x 'list))
	 (len (length list)))
    (when (< index 0)
      (incf index len)) ;; XXX this must be moved to an :around method or something
    (when (or (< index 0)
	      (> index (1- len)))
      (py-raise 'IndexError
		"List assignment index out of range (got: ~A, len: ~A)"
		index len))
    (setf (car (nthcdr index list)) new-item))
  x)

(defun list-setitem-slice (x slice new-items)
  (declare (ignore x slice new-items))
  (error "todo: setitem list slice")
  
  ;; new-items: iterable!
  #+(or)(let* ((list (slot-value x 'list))
	       (len (length list)))
	  (destructuring-bind (start stop step)
	      (tuple->lisp-list (indices slice len))
	    (when (< start 0)
	      (setf start 0))
	    (when (>= stop len)
	      (setf stop (1- len)))
      
	    (cond 
	     ((< stop start)) ;; bogus range: ignore)
	     ((= start stop)) ;; del empty range: ignore
	     ((= start 0)
	      (setf (slot-value x 'list)
		(nthcdr stop list)))
	     (t (let ((start-cons (nthcdr (1- start) x))
		      (rest-cons (nthcdr stop x))
		      (new-last-cons (last new-items)))
		  (setf (cdr start-cons) new-items
			(cdr new-last-cons) rest-cons)))))))


(defmethod __str__ ((x py-list))
  (format nil "[~:_~{~A~^, ~:_~}]"
	  (mapcar #'__str__ (slot-value x 'list))))


;;; list-specific methods

;; to ease debugging, for now the in-place operations return the
;; (modified) list they work on

(defmethod __reversed__ ((x py-list))
  "Return a reverse iterator"
  ;; new in Py ?.?
  (let ((rev (reverse (slot-value x 'list))))
    (make-iterator-from-function
     (lambda ()
       (pop rev)))))
  
(defmethod list-append ((x py-list) item)
  (setf (cdr (last (slot-value x 'list))) (cons item nil))
  x)

(defmethod list-count ((x py-list) item)
  (loop for i in (slot-value x 'list)
      count (__eq__ i item)))

(defmethod list-extend ((x py-list) iterable)
  (let ((res ()))
    (py-iterate (i iterable)
		(push i res))
    (setf (cdr (last (slot-value x 'list))) (nreverse res)))
  x)

(defmethod list-index ((x py-list) item &optional start stop)
  (let ((res (position-if (lambda (v) (__eq__ v item))
			  (slot-value x 'list)
			  :start (or start 0) :end stop)))
    (cond
     (res res)
     (start (py-raise 'ValueError
		      "list.index(x): value ~A not found in this part of the list"
		      item))
     (t (py-raise 'ValueError
		  "list.index(x): value ~A not found in this part of the list"
		  item)))))

(defmethod list-insert ((x py-list) index object)
  (ensure-py-type index integer
		  "list.insert(): index must be an integer (got: ~A)")
  (let ((list (slot-value x 'list)))
    (if (= index 0)
	(setf (slot-value x 'list) (cons object list))
      (let ((just-before (nthcdr (1- index) list))
	    (after (nthcdr index list)))
	(if (not after)
	    (setf (cdr (last list)) (cons object nil))
	  (setf (cdr just-before) (cons object after))))))
  x)

(defmethod list-pop ((x py-list) &optional index)
  (let* ((list (slot-value x 'list))
	 (len (length list)))

    (if index
	(progn (ensure-py-type index integer
			       "list.pop(x,i): index must be integer (got: ~A)")
	       (when (< index 0)
		 (incf index len)))
      (setf index (1- len)))
    
    (cond ((null list)
	   (py-raise 'IndexError
		     "Pop from empty list"))
	  
	  ((not (<= 0 index (1- len)))
	   (py-raise 'IndexError
		     "Pop index out of range (got: ~A, len: ~A)" index len))
	  
	  ((= index 0)
	   (setf (slot-value x 'list) (cdr list))
	   (car list))
	  
	  (t
	   (let ((cons-before (nthcdr (1- index) list)))
	     (prog1
		 (cadr cons-before)
	       (setf (cdr cons-before) (cddr cons-before))))))))

(defmethod list-remove ((x py-list) item)
  "Remove first occurance of item"
  (setf (slot-value x 'list)
    (delete item (slot-value x 'list) :test #'__eq__ :count 1))
  x)

(defmethod list-reverse ((x py-list))
  "In-place"
  (setf (slot-value x 'list)
    (nreverse (slot-value x 'list)))
  x)

(defmethod list-sort ((x py-list) &optional (cmpfunc *None*))
  "Stable sort, in-place"
  (let ((lt-pred (if (eq cmpfunc *None*)
		     #'py-<
		   (lambda (x y) (< (py-call cmpfunc (list x y)) 0)))))
    (setf (slot-value x 'list)
      (stable-sort (slot-value x 'list) lt-pred)))
  x)


;; XXX __str__ falls back to __repr__
;; XXX "x < y" => operator.lt => uses __lt__ if defined, otherwise __cmp__
;; XXX __lt__ never falls back to __cmp__

(def-class-specific-methods
    py-list
    ((append  #'list-append  :meth)
     (count   #'list-count   :meth)
     (extend  #'list-extend  :meth)
     (index   #'list-index   :meth)
     (insert  #'list-insert  :meth)
     (pop     #'list-pop     :meth)
     (remove  #'list-remove  :meth)
     (reverse #'list-reverse :meth)
     (sort    #'list-sort    :meth)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Iterator
;; 
;; <http://www.python.org/peps/pep-0234.html>
;; <<
;; The two methods correspond to two distinct protocols:
;;     1. An object can be iterated over with "for" if it implements
;;        __iter__() or __getitem__().
;;     2. An object can function as an iterator if it implements next().
;; >>

(defclass py-iterator (builtin-instance)
  ()
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-iterator))

(defmethod __iter__ ((x py-iterator))
  "It's defined that an iterator is its own iterator, so people
   can do:  for i in iter(iter(iter(iter(foo))))."
  x)

(defvar *StopIteration* '|stop-iteration|)

(defclass py-func-iterator (py-iterator)
  ((func :initarg :func :type function)
   (stopped-yet :initform nil)
   (end-value :initarg :end-value))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-func-iterator))

(defun make-iterator-from-function (f &optional (end-value nil))
  "Create an iterator that calls f again and again. (F somehow has to keep ~@
   its own state.) When F returns a value EQL to END-VALUE (default: nil), ~@
   it is considered finished and will not be called any more times."
  (check-type f function)
  (make-instance 'py-func-iterator :func f :end-value end-value))

(defmethod next ((f py-func-iterator))
  "This is the only function that an iterator has to provide."
  (when (slot-value f 'stopped-yet)
    #1=(py-raise 'StopIteration
		 "Iterator ~S has finished" f))
  (let ((res (funcall (slot-value f 'func))))
    (when (eql res (slot-value f 'end-value))
      (setf (slot-value f 'stopped-yet) t)
      #1#)
    res))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Tuple

(defclass py-tuple (builtin-instance)
  ((list :initarg :list :type list)
   #+(or)(length :initarg :length :type integer))
  (:documentation "The Tuple type")
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-tuple))

(defun make-tuple (&rest lst)
  "Make a Python tuple from the given CL list"
  (check-type lst list "A regular Lisp list")
  (make-instance 'py-tuple :list lst))

(defun make-tuple-from-list (list)
  (make-instance 'py-tuple :list list))

(defun tuple->lisp-list (tup)
  "internal use only"
  (slot-value tup 'list))


(defmethod tuple-__new__ (cls &rest options)
  (let ((instance
	 (cond ((not options) (make-tuple))
	       ((cdr options) (py-raise 'TypeError "tuple.__new__() takes at most 1 argument (got: ~A)" options))
	       (t             (make-tuple-from-list (py-iterate->lisp-list (car options)))))))
    (if (eq cls (find-class 'py-tuple))
	instance
      (if (and (typep cls 'class)
	       (subtypep cls (find-class 'py-tuple)))
	  (change-class instance cls)
	(py-raise 'TypeError "~S is not a subclass of ~S" cls (find-class 'py-tuple))))))

(register-as-__new__method #'tuple-__new__)

(defmethod __init__ ((x py-tuple) &optional pos-args kwd-args)
  (declare (ignore pos-args kwd-args)))

;;;; magic methods

;;; XXX Many methods are similar as for py-list. Maybe move some to a
;;; shared superclass py-sequence. However, the implementation of
;;; py-list is likely to change, in order to allow efficient
;;; lookup-by-index of O(1). This change might remove much of the
;;; redundancy.

(defmethod __add__ ((x py-tuple) (y py-tuple))
  (make-tuple-from-list
   (append (slot-value x 'list) (slot-value y 'list))))

;; CPython tuples: no __radd__

(defmethod __cmp__ ((x py-tuple) (y py-tuple))
  (__cmp-list__ (slot-value x 'list) (slot-value y 'list)))

(defmethod __contains__ ((x py-tuple) item)
  (if (some (lambda (y) (__eq__ item y))
	    (slot-value x 'list))
      *True*
    *False*))

(defmethod __getitem__ ((x py-tuple) item)
  (let ((list (slot-value x 'list)))
    (typecase item
      (py-int-designator (extract-list-item-by-index list item))
      (py-slice          (make-tuple-from-list (extract-list-slice list item)))
      (t                 (py-raise 'TypeError
				   "Tuple indices must be integers (got: ~A)" item)))))

(defmethod __hash__ ((x py-tuple))
  ;; Try to avoid  hash( (x,(x,y)) ) = hash( (y) )
  ;; so being a bit creative here...
  (let ((hash-values #(1274 9898982 1377773 -115151511))
	(res 23277775)
	(pos 0))
    (dolist (xi (slot-value x 'list))
      (setf res (logxor res 
			(+ (__hash__ xi)
			   (aref hash-values (mod pos 4)))))
      (incf pos))
    (mod-to-fixnum res)))
   
(defmethod __iter__ ((x py-tuple))
  (let ((list-copy (copy-list (slot-value x 'list)))) ;; copy-tree ?!
    (make-iterator-from-function
     (lambda ()
       (pop list-copy)))))

(defmethod __len__ ((x py-tuple))
  (length (slot-value x 'list)))

(defmethod __mul__ ((x py-tuple) (n integer))
  "structure is copied n times"
  ;; n <= 0 => empty list
  (make-tuple-from-list (loop for i from 1 to n
			    append (slot-value x 'list))))
  
(defmethod __rmul__ ((x py-tuple) (n integer)) 
  (__mul__ x n))

(defmethod __repr__ ((x py-tuple))
  (let ((list (slot-value x 'list)))
    (if list
	(with-output-to-string (s)
	  (format s "(~{~A,~^ ~})" (mapcar #'__repr__ list)))
      "(,)")))

;; __reversed__ ?

(defmethod __setitem__ ((x py-tuple) key val)
  (declare (ignore key val))
  (py-raise 'TypeError
	    "Cannot set items of tuples"))

;;; there are no tuple-specific methods
(def-class-specific-methods
    py-tuple
    ((__new__ #'tuple-__new__ :meth)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; String
;; 
;; Lisp strings are designators for Python string objects, but Lisp
;; characters are not.

(defclass py-string (builtin-instance)
  ((string :type string :initarg :string))
  (:documentation "The String type")
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-string))

(deftype py-string-designator ()
  `(or py-string string))

(defun py-string-designator-p (s)
  "Return STRING-DESIGNATOR-P, LISP-STRING"
  (cond ((typep s 'string) (values t s))
	((typep s 'py-string) (values t (slot-value s 'string)))
	(t nil)))
  
(defun make-py-string (&optional (s ""))
  (check-type s string "A Lisp string")
  (make-instance 'py-string :string s))

(defmethod py-string->symbol ((x py-string))
  (intern (slot-value x 'string)))

(defmethod print-object ((x py-string) stream)
  (print-unreadable-object (x stream :type t)
    (format stream "~S" (slot-value x 'string))))


(defmethod __mul-1__ ((x string) n)
  (multiple-value-bind (des val)
      (py-int-designator-p n)
    (unless des
      (return-from __mul-1__ *NotImplemented*))
    (setf n val))
  (let ((s ""))
    (loop for i from 1 to n
	do (setf s (concatenate 'string s x))
	finally (return s))))


;;; string-specific methods

(defmethod string-center-1 ((s string) width)
  "'a'.center(2) -> 'a '"
  (ensure-py-type width integer "string.center() requires integer width (got: ~A)")
  (let* ((len (length s))
	 (diff (- width len)))
    (if (> diff 0)
	(let* ((before (floor (/ diff 2)))
	       (v (make-array (max width len) :element-type 'character)))
	  (loop for i from 0 below before
	      do (setf (aref v i) #\Space))
	  (loop for c across s
	      for i from before
	      do (setf (aref v i) c))
	  (loop for i from (+ before len) below width
	      do (setf (aref v i) #\Space))
	  v)
      s)))

(defmethod string-count-1 ((x string) (sub string))
  "Count number of occurances of SUB in X."
  (let ((count 0)
	(start-pos 0)
	(sublen (length sub)))
    (loop
      (let ((res (search sub x :start2 start-pos)))
	(if res
	    (progn
	      (incf count)
	      (setf start-pos (+ res sublen))) ;; "aaa".count("aa") = 1
	  (return))))
    count))

(defmethod string-decode-1 (x &optional encoding errors)
  (declare (ignore x encoding errors))
  (error "todo: string-decode"))

(defmethod string-encode-1 (x &optional encoding errors)
  (declare (ignore x encoding errors))
  (error "todo: string-decode"))

(defmethod string-endswith-1 ((x string) (suffix string) &optional (start 0) (end nil))
  (ensure-py-type start integer "String indices must be integers (got: ~A)")
  (when end
    (ensure-py-type end integer "String indices must be integers (got: ~A)"))
  
  (when (string= suffix "") ;; trivial
    (return-from string-endswith-1 t))
  
  (destructuring-bind (start stop step)
      (tuple->lisp-list (indices (make-slice start (or end (1- (length x))) 1)
				 (length x)))
    (declare (ignore step))
    (let ((subseq-start (- (1+ stop) (length suffix))))
      
      (when (< subseq-start start)
	(return-from string-endswith-1 nil))
		  
      (string= (subseq x subseq-start (1+ stop))
	       suffix))))

(defmethod string-expandtabs-1 ((x string) &optional (tabsize 8))
  (ensure-py-type tabsize integer "string.expandtabs: tabsize must be integer (got: ~A)")
  (let ((s (make-array (length x) :element-type 'character :adjustable t :fill-pointer 0)))
    (loop for c across x
	do (if (char= c #\Tab)
	       (dotimes (i tabsize)
		 (vector-push-extend #\Space s))
	     (vector-push-extend c s)))
    s))

(defmethod string-find-1 ((x string) (sub string) &optional (start 0) end)
  (ensure-py-type start integer "String indices must be integers (got: ~A)")
  (when end
    (ensure-py-type end integer "String indices must be integers (got: ~A)"))

  (when (string= sub "") ;; trivial
    (return-from string-find-1 0))

  (destructuring-bind (start stop step)
      (tuple->lisp-list (indices (make-slice start (or end (1- (length x))) 1)
				 (length x)))
    (declare (ignore step))
    (let ((res (search sub (subseq x start stop))))
      (if res
	  (+ start res)
	-1))))

(defmethod string-index-1 ((x string) (sub string) start end)
  (let ((res (string-find-1 x sub start end)))
    (if (= res -1)
	(py-raise 'ValueError "Substring not found")
      res)))

;; Predicates

(defmethod string-isalnum-1 ((x string))
  (lisp-val->py-bool (every #'alphanumericp x)))

(defmethod string-isalpha-1 ((x string))
  (lisp-val->py-bool (every #'alpha-char-p x)))

(defmethod string-isdigit-1 ((x string))
  (lisp-val->py-bool (every #'digit-char-p x)))

(defmethod string-islower-1 ((x string))
  (lisp-val->py-bool (every #'lower-case-p x)))

(defmethod string-isspace-1 ((x string))
  (lisp-val->py-bool (every (lambda (c) (member c (load-time-value (list #\Space #\Tab #\Newline))))
		    ;; XX check what is whitespace
		    x)))

(defmethod string-istitle-1 ((x string))
  ;; It is defined to be a titel iff first char uppercase, rest lower; with anything non-alpha (even
  ;; non-printable characters) in between, like "Abc De"
  ;; 
  ;; Algorithm taken from `Objects/stringobject.c', function `string_istitle'.
  (let ((got-cased nil)
	(previous-is-cased nil))
    (loop for c across x
	do (cond ((upper-case-p c) (when previous-is-cased
				     (return-from string-istitle-1 *False*))
				   (setf previous-is-cased t)
				   (setf got-cased t))
		 
		 ((lower-case-p c) (unless previous-is-cased
				     (return-from string-istitle-1 *False*)))
		 
		 (t 		   (setf previous-is-cased nil))))
    (lisp-val->py-bool got-cased)))

  
(defmethod string-isupper-1 ((x string))
  (lisp-val->py-bool (every #'upper-case-p x)))

(defmethod string-join-1 ((x string) sequences)
  "Join a number of strings"
  (let ((acc ()))
    (py-iterate (str sequences)
		(format t "str: ~S~%" str)
		(ensure-py-type str string
				"string.join() can only handle real strings (got: ~A)")
		(push str acc))
    (apply #'concatenate 'string x (nreverse acc))))


(defmacro def-unary-string-meths (data)
  `(progn ,@(loop for (name args body) in data
		do (assert (eq (car args) 'x))
		collect (let ((rest (cdr args)))
			  `(progn (defmethod ,name ((x py-string) ,@rest)
				    (let ((x (slot-value x 'string)))
				      ,body))
				  (defmethod ,name ((x string) ,@rest)
				    ,body))))))

(defmacro def-binary-string-meths (names)
  `(progn ,@(loop for (name args body) in names
		do (assert (and (eq (first args) 'x)
				(eq (second args) 'y)))
		collect (let* ((rest (cddr args))
			       (rest2 (remove '&optional rest)))
			  `(progn (defmethod ,name ((x py-string) y ,@rest)
				    (let ((x (slot-value x 'string)))
				      (,name x y ,@rest2)))
				  (defmethod ,name (x (y py-string) ,@rest)
				    (let ((y (slot-value y 'string)))
				      (,name x y ,@rest2)))
				  (defmethod ,name ((x string) (y string) ,@rest)
				    ,body))))))

(def-unary-string-meths 
    ((__getitem__ (x index) (progn (ensure-py-type index integer "String indices must be integer (slices: todo)")
				   (when (< index 0) ;; XXX slice support
				     (incf index (length x)))
				   (string (char x index))))
     (__hash__  (x) (sxhash x))
     (__iter__  (x) (let ((i 0))
		      (make-iterator-from-function
		       (lambda () (when (< i (length x))
				    (prog1 (string (aref x i))
				      (incf i)))))))
     (__len__  (x) (length x))
     (__mod__  (x args) (locally (declare (ignore x args))
			  (error "todo: string mod")))
     ;; rmod, rmul
     (__mul__  (x n) (__mul-1__ x n))
     
     ;; __reduce__ : todo
     
     ;; __repr__ : with quotes (todo: if string contains ', use " as quote etc)
     ;; __str__  : without surrounding quotes
     (__repr__ (x) (format nil "~S" x))
     (__str__  (x) (format nil "~A" x))
     
     (py-string-capitalize (x) (string-capitalize x)) ;; Lisp function
     (string-center (x width)                     (string-center-1 x width))
     (string-decode (x &optional encoding errors) (string-decode-1 x encoding errors))
     (string-encode (x &optional encoding errors) (string-encode-1 x encoding errors))
     (string-expandtabs (x &optional tabsize)     (string-expandtabs-1 x tabsize))
     (string-isalnum (x)  (string-isalnum-1 x))
     (string-isalpha (x)  (string-isalpha-1 x))
     (string-isdigit (x)  (string-isdigit-1 x))
     (string-islower (x)  (string-islower-1 x))
     (string-istitle (x)  (string-istitle-1 x))
     (string-isupper (x)  (string-isupper-1 x))
     (string-join    (x seq) (string-join-1 x seq))))

(def-binary-string-meths
    ((__add__      (x y)  (concatenate 'string x y))
     (__radd__     (x y)  (__add__ y x))
     (__contains__ (x y)  (lisp-val->py-bool (search y x)))
     (__cmp__ (x y)       (cond ((string< x y) -1)
			        ((string= x y) 0)
			        (t 1)))
     (__eq__ (x y)        (string= x y))
     
     (string-count    (x y) (string-count-1 x y))
     (string-endswith (x y &optional start end)  (lisp-val->py-bool (string-endswith-1 x y start end)))
     (string-find     (x y &optional start end)  (string-find-1 x y start end))
     (string-index    (x y &optional start end)  (string-index-1 x y (or start 0) (or end 0)))))


(def-class-specific-methods
    py-string
    ((capitalize #'string-capitalize :meth) ;; lisp function
     (center   #'string-center-1   :meth)
     (decode   #'string-decode-1   :meth)
     (encode   #'string-encode-1   :meth)
     (expandtabs  #'string-expandtabs-1  :meth)
     (isalnum  #'string-isalnum-1  :meth)
     (isalpha  #'string-isalpha-1  :meth)
     (isdigit  #'string-isdigit-1  :meth)
     (islower  #'string-islower-1  :meth)
     (istitle  #'string-istitle-1  :meth)
     (isupper  #'string-isupper-1  :meth)
     (join     #'string-join-1     :meth)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; File

;; XXX all this file object stuff is untested!

(defclass py-file (builtin-instance)
  ((stream :type file-stream)
   (newlines :initform ()) ;; list possibly containing 'n, 'r, 'rn
   ))

(defmethod file-check-open ((f py-file) &optional direction)
  (with-slots (stream) f
    (let ((open (and (open-stream-p stream)
		     (ecase direction
		       (nil t)
		       (:input (input-stream-p stream))
		       (:output (output-stream-p stream))))))
      (unless open
	(py-raise 'ValueError "I/O operation on closed file")))))

(defmethod file-close ((f py-file))
  ;; Calling CLOSE more than once is allowed in Python. No return value.
  (with-slots (closed stream) f
    (unless closed
      (close stream)))
  (values))

(defmethod file-flush ((f py-file))
  ;; Flush internal buffer.
  (file-check-open f)
  (with-slots (stream) f
    (when (and (open-stream-p stream)
	       (output-stream-p stream))
      (finish-output stream))
    (when (and (open-stream-p stream)
	       (input-stream-p stream))
      ;; call CLEAR-INPUT ?
      ))
  (values))

(defmethod file-fileno ((f py-file))
  (py-raise 'NotImplementedError
	    "Sorry, method `fileno' of file objects not implemented"))

(defmethod file-isatty ((f py-file))
  (py-raise 'NotImplementedError
	    "Sorry, method `isatty' of file objects not implemented"))

(defmethod __iter__ ((f py-file))
  ;; The PY-FILE itself implements NEXT.
  (file-check-open f :input)
  (file-readline f))

(defmethod next ((f py-file))
  (file-readline f))

(defmethod file-read ((f py-file) &optional (size nil size-p))
  (when size-p
    (ensure-py-type size integer
		    "Argument SIZE to file.read() must be ~@
                     positive integer (got: ~A)")
    (unless (>= size 0)
      (py-raise 'ValueError
		"Argument SIZEHINT to file.read() must be ~@
                 positive integer (got: ~A)" size)))
  
  (with-slots (stream newlines) f
    (let ((count 0)
	  (res (make-array 1000
			   :element-type 'character
			   :adjustable t
			   :fill-pointer 0)))
      (loop
	(when (and size-p
		   (= size count))
	  (return-from file-read res))
	(let ((ch (read-char stream nil nil)))
	  (if ch
	      (vector-push-extend ch res)
	    (return-from file-read res)))))))


(defmethod file-readline ((f py-file) &optional (maxsize nil maxsize-p))
  ;; Returns LINE, NUM-READ
  ;; Because Lisp doesn't treat "\r" as newline, we have to do this
  ;; ourselves (?).
  
  (file-check-open f :input)
  
  (when maxsize-p
    (ensure-py-type maxsize integer
		    "Argument SIZEHINT to file.readline() must be ~@
                     positive integer (got: ~A)")
    (unless (>= maxsize 0)
      (py-raise 'ValueError
		"Argument SIZEHINT to file.readline() must be ~@
                 positive integer (got: ~A)" maxsize)))
  (with-slots (stream newlines) f
    (let ((res (make-array 100
			   :element-type 'character
			   :adjustable t
			   :fill-pointer 0))
	  (num-read 0))
      (loop
	
	(when (and maxsize-p
		   (= num-read maxsize))
	  (return-from file-readline (values res num-read)))
	
	(let ((ch (read-char stream nil :eof)))
	  (case ch
	    (:eof	     (return-from file-readline (values res num-read)))
	    (#\Newline       (vector-push-extend ch res) ; '\n\
			     (pushnew 'n newlines)
			     (return-from file-readline (values res num-read)))
	    (#\Return        (vector-push-extend ch res) ; '\r' or '\r\n'
			     (let ((ch2 (peek-char nil stream nil :eof)))
			       (case ch2
				 (:eof            (pushnew 'r newlines)
						  (return-from file-readline (values res num-read)))
				 (#\Newline       (vector-push-extend ch2 res)
						  (pushnew 'rn newlines)
						  (return-from file-readline (values res num-read)))
				 (t               (return-from file-readline (values res num-read))))))))))))


(defmethod file-readlines ((f py-file) &optional (sizehint nil sizehint-p))
  (when sizehint-p
    (ensure-py-type sizehint integer
		    "Argument SIZEHINT to file.readlines() must be ~@
                     positive integer (got: ~A)")
    (unless (>= sizehint 0)
      (py-raise 'ValueError
		"Argument SIZEHINT to file.readlines() must be ~@
                 positive integer (got: ~A)" sizehint)))
  
  (let ((res ())
	(num-read 0))
    (loop
      (multiple-value-bind (line n)
	  (file-readline f)
	(push line res)
	(when sizehint-p
	  (incf num-read n)
	  (when (<= sizehint num-read)
	    (return)))))
    (make-py-list-from-list (nreverse res))))


(defmethod file-xreadlines ((f py-file))
  (__iter__ f))


(defmethod file-seek ((f py-file) offset &optional (whence nil whence-p))
  ;; Set FILE position.
  ;; Whence: 0 = absolute; 1 = relative to current; 2 = relative to end
  ;; There is no return value, but an IOError is raised for invalid arguments.
  
  (ensure-py-type offset integer
		  "file.seek() OFFSET argument must be integer (got: ~A)")
  (let ((reference
	 (if whence-p
	     (progn (ensure-py-type whence integer
				    "file.seek() WHENCE argument must be integer (got: ~A)")
		    (case whence
		      (0 :absolute)
		      (1 :current)
		      (2 :end)
		      (t (py-raise 'ValueError
				   "file.seek() WHENCE argument not in 0..2 (got: ~A)" whence))))
	   :absolute)))
    
    (file-check-open f)
    (with-slots (stream) f      
      (ecase reference
	    
	(:absolute
	 (cond ((>= offset 0) (unless (file-position stream offset)
				(py-raise 'IOError
					  "File seek failed (absolute; offset: ~A)"
					  offset))) ;; catch more?
	       ((< offset 0) (py-raise 'IOError
				       "Negative offset invalid for absolute file.seek() (got: ~A)"
				       offset))))
	     
	(:end   ;; XX check off-by-one for conditions
	 (cond ((<= offset 0) (unless (file-position stream (+ (file-length stream) offset))
				(py-raise 'IOError
					  "File seek failed (from-end; offset: ~A)"
					  offset)))
	       ((> offset 0) (py-raise 'IOError
				       "Positive offset invalid for file.seek() from end (got: ~A)"
				       offset))))
	(:relative
	 (unless (unless (file-position stream (+ (file-position stream) offset))
		   (py-raise 'IOError
			     "File seek failed (relative; offset: ~A)"
			     offset))))))))
	      
(defmethod file-tell ((f py-file))
  (with-slots (stream) f
    (file-position stream)))

(defmethod file-truncate ((f py-file) &optional (size nil size-p))
  (file-check-open f) ;; or not needed?
  (with-slots (stream) f
    (if size-p
	(progn
	  (ensure-py-type size integer
			  "file.truncate() expects non-negative integer arg (got: ~A)")
	  (when (< size 0)
	    (py-raise 'ValueError
		      "File.truncate() expects non-negative integer (got :~A)" size)))
      (setf size (file-position stream)))
    #+:allegro (handler-case (excl.osi::os-ftruncate f size)
		 (excl.osi:syscall-error ()
		   (py-raise 'IOError "Truncate failed (syscall-error)")))))
		 
(defmethod file-write ((f py-file) str)
  (ensure-py-type str string "file.write() takes string as arg (got: ~A)")
  (file-check-open f :output)
  (with-slots (stream) f
    (write-string str stream)))
   
(defmethod file-writelines ((f py-file) seq)
  (py-iterate (str seq)
	      (ensure-py-type str string
			      "file.writelines() requires sequence of strings (got element: ~A)")
	      (file-write f str)))

(defmethod file-closed ((f py-file))
  (with-slots (stream) f
    (not (open-stream-p stream))))

(defmethod file-encoding ((f py-file))
  (py-raise 'NotImplementedError
	    "Sorry, method `fileno' of file objects not implemented"))

(defmethod file-mode ((f py-file))
  ;; easy to add
  (py-raise 'NotImplementedError
	    "Sorry, method `fileno' of file objects not implemented"))

(defmethod file-name ((f py-file))
  ;; easy to add
  (py-raise 'NotImplementedError
	    "Sorry, method `fileno' of file objects not implemented"))
  
(defmethod file-newlines ((f py-file))
  ;; Return a tuple with the encountered newlines as strings.
  (with-slots (newlines) f
    (make-tuple-from-list (mapcar (lambda (nl)
				    (ecase nl
				      (r (string #\Return))
				      (n (string #\Newline))
				      (rn (format nil "~A~A" #\Return #\Newline))))
				  newlines))))

#+(or) ;; should we implement this, or is it a CPython implementation detail?!
(defmethod file-softspace ((f py-file))
  )


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Enumerate
;; 
;; Generator to iterate over an object, also yielding the index of the yielded item:
;; 
;; >>> x = enumerate("asdf")
;; >>> x
;; <enumerate object at 0x4021b6ac>
;; >>> x.next()
;; (0, 'a')
;; >>> x.next()
;; (1, 's')

(defclass py-enumerate (builtin-instance)
  ((generator :initarg :generator)
   (index :initarg :index :type integer))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-enumerate))

(defun make-enumerate (iterable)
  (make-instance 'py-enumerate
    :index 0
    :generator (__iter__ iterable)))

(defmethod __iter__ ((x py-enumerate))
  x)

(defmethod next ((x py-enumerate))
  ;; Will raise StopIteration as soon as (next generator) does that.
  (with-slots (index generator) x
    (prog1
	(make-tuple index (next generator))
      (incf index))))
    

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; XRange object
;; 
;; Like built-in function `range', but lazy. It's a type of its own.

(defclass py-xrange (builtin-instance)
  ((start :type integer :initarg :start)
   (stop  :type integer :initarg :stop)
   (step  :type integer :initarg :step)
   (max-num-steps :type integer :initarg :max-num-steps))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-xrange))

(defun make-xrange (x &optional y z)
  ;; XX is there a need to check step has right sign? (also range())
  (flet ((xrange-2 (start stop step)
	   (ensure-py-type (start stop step) integer
			   "arguments to xrange() must be int (got: ~A)")
	   (let (max-num-steps)
	     (cond
	      ((or (and (< start stop)
			(< 0 step))
		   (and (> start stop)
			(> 0 step)))
	       ;; range ok
	       (setf max-num-steps (floor (/ (- (- stop 1) start)
					     step)))
	       (setf stop (+ start (* step max-num-steps))))
	    
	      (t
	       ;; bogus range: return no values at all
	       (setf start 0 stop 0 step 0 max-num-steps 0)))
	   
	     (make-instance 'py-xrange :start start :stop stop
			    :step step :max-num-steps max-num-steps))))
    
    (cond (z (xrange-2 x y z))
	  (y (xrange-2 x y 1))
	  (t (xrange-2 0 x 1)))))

(defmethod __iter__ ((x py-xrange))
  (let* ((start (slot-value x 'start))
	 (stop (slot-value x 'stop))
	 (step (slot-value x 'step))
	 (i start)
	 (stopped-already (= i stop)))
    (make-iterator-from-function
     (lambda ()
       (unless stopped-already
	 (setf stopped-already (= i stop))
	 (prog1 i
	   (incf i step)))))))

(defmethod __getitem__ ((x py-xrange) index)
  (ensure-py-type index integer
		  "index arguments to xrange[] must be int (got: ~A)")
  (let ((start (slot-value x 'start))
	(stop (slot-value x 'stop))
	(step (slot-value x 'step))
	(max-num-steps (slot-value x 'max-num-steps)))
    
    (cond ((and (>= index 0)
		(<= index max-num-steps))
	   (+ start (* step index)))
	  ((and (< index 0)
		(>= index (- max-num-steps)))
	   (- stop (* step (1+ index)))) ;; 1+ because `stop' is one too far
	  (t
	   (py-raise 'IndexError
		     "xrange(~A,~A,~A) index out of range (got: ~A)"
		     start stop step index)))))

(defmethod __len__ ((x py-xrange))
  (1+ (slot-value x 'max-num-steps)))

(defmethod print-object ((x py-xrange) stream)
  (print-unreadable-object (x stream :identity t :type t)
    (with-slots (start stop step) x
      (format stream ":start ~A  :stop ~A  :step ~A" start stop step))))

(defmethod __hash__ ((x py-xrange))
  (mod-to-fixnum (logxor (slot-value x 'start)
			 (slot-value x 'stop)
			 (slot-value x 'step))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Slice object
;; 
;; Denotes sub-items of a sequence-like object.
;; 
;; slice( [start,] stop [, step )
;;
;; foo[a] -> foo.__getitem__(a)
;; foo[a:b] -> foo.__getitem__( slice(a,b,None) )
;; foo[a:b:c] -> foo.__getitem__( slice(a,b,c) )
;; 
;; However, there's interplay with `Ellipsis':
;; 
;; foo[1:2,...,4:3]
;;  -> foo.__getitem__(
;;           (slice(1, 2, None), Ellipsis, slice(4, 3, None))  <-- tuple!
;;     )

(defclass py-slice (builtin-instance)
  ((start :initarg :start) ;; these can be any type
   (stop  :initarg :stop)
   (step :initarg :step))
  (:metaclass builtin-class))

(mop:finalize-inheritance (find-class 'py-slice))

(defun make-slice (x &optional y z)
  ;; X,Y,Z don't have to be integers
  (cond (z (make-instance 'py-slice  :start x       :stop y  :step z))
	(y (make-instance 'py-slice  :start x       :stop y  :step *None*))
	(t (make-instance 'py-slice  :start *None*  :stop x  :step *None*))))

(defmethod print-object ((x py-slice) stream)
  (print-unreadable-object (x stream :type t)
    (with-slots (start stop step) x
      (format stream ":start ~A  :stop ~A  :step ~A" start stop step))))

(defmethod indices ((x py-slice) length)
  "Return tuple with three integers: start, stop, step.~@
   In case of empty range, returns (length,length,1)."
  (multiple-value-bind (start stop step)
      (slice-indices x length)
    (make-tuple start stop step)))

(defmethod slice-indices ((x py-slice) length)
  "Return 1 or 4 values (nonempty, start, stop, step) indicating requested slice.
   nonempty: T or nil
   if nonempty is T: START is the index of the first item of the resulting slice
                     STOP the index of the last item
                     STEP the amount by which to increase each time (can be negative; is not zero)
                     if step > 0:
                       0 <= start <= stop <= length-1
                     if step < 0:
                       0 <= stop <= start <= length-1"

  ;; CPython doesn't define the outcome of this method exactly. Like,
  ;; where is this documented:
  ;; 
  ;;  >>> s = slice(10,15,-1)
  ;;  >>> s.indices(5)
  ;;  (4, 5, -1)
  ;; 
  ;; (For such cases, maybe Python should have a way to specify 'empty
  ;; slice', for clarity.)
  ;; 
  ;; Here's what we do, for slice [x:y:s] and len L. (For CPython
  ;; compatibility, indices are required to be integers.)
  ;; 
  ;;  s == 0        [1:10: 0]  => error
  ;; 
  ;; Then, if X or Y is < 0, one time the length L is added to it.
  ;; Then we proceed as follows:
  ;; 
  ;;  x == y        [4: 4: 1]  => empty slice (L,L,1)
  ;;  x < y, s > 0  [2:10: 1]  => ok: (2,10,1)  (x < 0 => x = 0;  y > L => x = L)
  ;;  x < y, s < 0  [1:10:-1]  => empty slice (L,L,1)
  ;;  x > y, s < 0  [10:1:-2]  => ok: (10,1,-2)  (x > L => x = L;  y < 0 => y = 0)
  ;;  x > y, s < 0  [10:1:-1]  => empty slice (L,L,1)
  
  (ensure-py-type length integer
		  "Argument to 'indices' method must be integer (got: ~A)")
  (let ((start (slot-value x 'start))
	(stop  (slot-value x 'stop))
	(step  (slot-value x 'step)))
    
    (if (eq start *None*)
	(setf start 0)
      (progn (ensure-py-type start integer "Slice indices must be integers (got: ~A)")
	     (when (< start 0)
	       (incf start length))))
    
    (if (eq stop *None*)
	(setf stop length)
      (progn (ensure-py-type stop integer "Slice indices must be integers (got: ~A)")
	     (when (< stop 0)
	       (incf stop length))))
    
    (if (eq step *None*)
	(setf step 1)
      (ensure-py-type step integer "Slice indices must be integers (got: ~A)"))
    
    (flet ((empty-slice ()
	     (values nil)))
      
      (cond ((= step 0) 	  (py-raise 'ValueError "Slice step cannot be zero"))
       	    
	    ((= start stop)	  (empty-slice))
            
	    ((and (>= start length)
		  (> step 0))     (empty-slice))
	    
	    ((and (< start 0)
		  (< step 0))     (empty-slice))
	    
	    ((and (< start stop)
		  (> step 0))	  (let ((start (max start 0))
					(stop  (min stop length))
					(real-stop (+ start (* step (floor (- stop 1 start)
									   step)))))
				    (assert (<= real-stop stop))
				    (values t start real-stop step)))
	    
	    ((and (< start stop)
		  (< step 0))	  (empty-slice))

	    ((and (> start stop)
		  (< step 0))	  (let ((start (min start length))
					(stop  (max stop 0))
					(real-stop (+ start (* step (floor (- stop -1 start)
									   step)))))
				    (assert (>= real-stop stop))
				    (values t start real-stop step)))
	    
	    ((and (> start stop)
		  (> step 0))	  (empty-slice))))))


(defmethod extract-list-slice ((list cons) (slice py-slice))
  "Given a (Lisp) list, extract the sublist corresponding to the slice as a fresh list."
  (multiple-value-bind (nonempty start stop step)
      (slice-indices slice (length list))
    
    (unless nonempty
      (return-from extract-list-slice (make-py-list)))
    
    (let ((in-reverse (< step 0)))
      
      (when in-reverse
	(rotatef start stop)
	(setf step (* -1 step)))
      
      (let* ((current (subseq list start (1+ stop)))
	     (acc ())
	     (i start))
	(loop
	  (push (car current) acc)
	  (cond ((= i stop) (return-from extract-list-slice
			      (if in-reverse
				  acc
				(nreverse acc))))
		((null current) (error "internal error: slice indices incorrect")))
	  (setf current (nthcdr step current))
	  (incf i step))))))


(defmethod extract-list-item-by-index ((list cons) (index integer))
  ;; todo: support subclassed integers
  (ensure-py-type index integer
		  "internal error: ~A")
  (let ((len (length list)))
    
    (when (< index 0)
      (incf index len))
    
    (when (or (< index 0)
	      (> index (1- len)))
      (py-raise 'IndexError
		"List index out of range (got: ~A, valid range: 0..~A)"
		index (- len 1)))
    
    (nth index list)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Type
;; 
;; The Python type from which all other types (classes) are derived.
;; It is defined in classes.cl.

#+(or)
(defmethod __call__ ((x (eql (find-class 'python-type))) &optional pos key)
  (declare (ignorable pos key))
  (break "__call__ on `type'"))
  


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; General Python object stuff


(deftype attribute-name-designator ()
  `(or symbol string))

(defun attribute-name-designator-p (x)
  "Return ATT-DES-P, SYMBOL"
  (typecase x
    (symbol (values t x))
    (string (values t (make-interned-string x)))
    (t      nil)))


;;;; python object?

(deftype python-object-designator ()
  `(or python-object number))

(defgeneric python-object-designator-p (x)
  (:documentation "Returns DESIGNATOR-P, PYVAL where PYVAL is a ~
                   Python object iff DESIGNATOR-P "))

;; shield this class from Python
(defmethod python-object-designator-p ((x (eql (find-class 'builtin-instance)))) (values nil nil))

(defmethod python-object-designator-p ((x python-object)) (values t x))
(defmethod python-object-designator-p ((x (eql (find-class 'python-type)))) (values t x))
(defmethod python-object-designator-p ((x number)) (values t (make-py-number x)))
(defmethod python-object-designator-p ((x string)) (values t (make-py-string x)))
(defmethod python-object-designator-p (x) (declare (ignore x)) nil)



;;;; builtin object?

(defgeneric builtin-object-designator-p (x)
  (:documentation "Returns DESIGNATOR-P"))

;; basically, everything except user-defined stuff
(defmethod builtin-object-designator-p (x)
  (declare (ignore x))
  t)

(defmethod builtin-object-designator-p ((x user-defined-object))
  nil)
