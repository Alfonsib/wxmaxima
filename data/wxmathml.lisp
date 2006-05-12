(in-package :maxima)

;; wxMaxima xml format (based on David Drysdale MathML printing)
;; Andrej Vodopivec, 2004-2006

;; MathML-printing
;; Created by David Drysdale (DMD), December 2002/January 2003
;;
;; closely based on the original TeX conversion code in mactex.lisp,
;; for which the following credits apply:
;;   (c) copyright 1987, Richard J. Fateman
;;   small corrections and additions: Andrey Grozin, 2001
;;   additional additions: Judah Milgram (JM), September 2001
;;   additional corrections: Barton Willis (BLW), October 2001

;; Method:

;; Producing wxxml from a macsyma internal expression is done by
;; a reversal of the parsing process.  Fundamentally, a
;; traversal of the expression tree is produced by the program,
;; with appropriate substitutions and recognition of the
;; infix / prefix / postfix / matchfix relations on symbols. Various
;; changes are made to this so that MathML will like the results.

;;(macsyma-module wxxml)

(declare-top
 (special lop rop ccol $gcprint texport $labels $inchar maxima-main-dir)
 (*expr wxxml-lbp wxxml-rbp))

(defun wxxml (x l r lop rop)
  ;; x is the expression of interest; l is the list of strings to its
  ;; left, r to its right. lop and rop are the operators on the left
  ;; and right of x in the tree, and will determine if parens must
  ;; be inserted
  (setq x (nformat x))
  (cond ((atom x) (wxxml-atom x l r))
        ((or (<= (wxxml-lbp (caar x)) (wxxml-rbp lop))
             (> (wxxml-lbp rop) (wxxml-rbp (caar x))))
         (wxxml-paren x l r))
        ;; special check needed because macsyma notates arrays peculiarly
        ((memq 'array (cdar x)) (wxxml-array x l r))
        ;; dispatch for object-oriented wxxml-ifiying
        ((get (caar x) 'wxxml) (funcall (get (caar x) 'wxxml) x l r))
        ((equal (get (caar x) 'dimension) 'dimension-infix)
         (wxxml-infix x l r))
        (t (wxxml-function x l r nil))))

(defun string-substitute (newstring oldchar x &aux matchpos)
  (setq matchpos (position oldchar x))
  (if (null matchpos) x
      (concatenate 'string
		   (subseq x 0 matchpos)
		   newstring
		   (string-substitute newstring oldchar
				      (subseq x (1+ matchpos))))))

;;; First we have the functions which are called directly by wxxml and its
;;; descendents

(defun wxxml-atom (x l r)
  (append l
          (list (cond ((numberp x) (wxxmlnumformat x))
                      ((typep x 'structure-object)
		       (strcat "<v>Lisp structure: " (type-of x) " </v>"))
                      ((mstringp x)
                       (let*
                           ((tmp-x (maybe-invert-string-case (symbol-name (stripdollar x))))
                            (tmp-x (string-substitute "&amp;" #\& tmp-x))
                            (tmp-x (string-substitute "&lt;" #\< tmp-x))
                            (tmp-x (string-substitute "&gt;" #\> tmp-x)))
                         (strcat "<st>" tmp-x "</st>")))
                      ((and (symbolp x) (get x 'wxxmlword))
		       (wxxml-stripdollar (get x 'wxxmlword)))
                      ((and (symbolp x) (get x 'reversealias))
                       (wxxml-stripdollar (get x 'reversealias)))
                      (t (wxxml-stripdollar x))
		      ))
	  r))

(defun wxxmlnumformat (atom)
  (let (r firstpart exponent)
    (cond ((integerp atom)
           (format nil "<n>~{~c~}</n>" (exploden atom)))
	  (t
	   (setq r (exploden atom))
	   (setq exponent (member 'e r :test #'string-equal))
	   (cond ((null exponent)
		  (format nil "<n>~{~c~}</n>" r))
		 (t
		  (setq firstpart
			(nreverse (cdr (member 'e (reverse r)
                                               :test #'string-equal))))
		  (format nil 
			  "<r><n>~{~c~}</n><h>*</h><e><n>10</n><n>~{~c~}</n></e></r>"
			  firstpart (cdr exponent))))))))

(defun wxxml-stripdollar (sym)
  (or (symbolp sym)
      (return-from wxxml-stripdollar sym))
  (let* ((pname (maybe-invert-string-case (symbol-name sym)))
         (pname (if (memq (elt pname 0) '(#\$ #\&)) (subseq pname 1) pname))
         (pname (string-substitute "&amp;" #\& pname))
         (pname (string-substitute "&gt;" #\> pname))
         (pname (string-substitute "&lt;" #\< pname)))
    (concatenate 'string "<v>" pname "</v>")))

(defun wxxml-paren (x l r)
  (wxxml x (append l '("<p>")) (cons "</p>" r) 'mparen 'mparen))

(defun wxxml-array (x l r)
  (let ((f))
    (if (eq 'mqapply (caar x))
	(setq f (cadr x)
	      x (cdr x)
	      l (wxxml f (append l (list "<i><r>")) nil
                       'mparen 'mparen))
	(setq f (caar x)
	      l (wxxml (wxxmlword f) (append l '("<i><r>"))
		       nil lop 'mfunction)))
    (setq r (nconc (wxxml-list (cdr x) (list "</r><r>")
                               (list "</r></i>") "<v>,</v>") r))
    (nconc l r)))

;; set up a list , separated by symbols (, * ...)  and then tack on the
;; ending item (e.g. "]" or perhaps ")"
(defun wxxml-list (x l r sym)
  (if (null x) r
      (do ((nl))
	  ((null (cdr x))
	   (setq nl (nconc nl (wxxml (car x)  l r 'mparen 'mparen)))
	   nl)
        (setq nl (nconc nl (wxxml (car x)  l (list sym) 'mparen 'mparen))
              x (cdr x)
              l nil))))

;; we could patch this so sin x rather than sin(x), but instead we made
;; sin a prefix operator
(defun wxxml-function (x l r op) op
       (setq l (wxxml (wxxmlword (caar x)) (append l '("<fn>"))
		      nil 'mparen 'mparen)
	     r (wxxml (cons '(mprogn) (cdr x)) nil (append '("</fn>") r)
		      'mparen 'mparen))
       (append l r))

;;; Now we have functions which are called via property lists

(defun wxxml-prefix (x l r)
  (wxxml (cadr x) (append l (wxxmlsym (caar x))) r (caar x) rop))

(defun wxxml-infix (x l r)
  ;; check for 2 args
  (if (or (null (cddr x)) (cdddr x)) (wna-err (caar x)))
  (setq l (wxxml (cadr x) l nil lop (caar x)))
  (wxxml (caddr x) (append l (wxxmlsym (caar x))) r (caar x) rop))

(defun wxxml-postfix (x l r)
  (wxxml (cadr x) l (append (wxxmlsym (caar x)) r) lop (caar x)))

(defun wxxml-nary (x l r)
  (let* ((op (caar x))
         (sym (wxxmlsym op))
         (y (cdr x))
         (ext-lop lop)
         (ext-rop rop))
    (cond ((null y)
	   (wxxml-function x l r t)) ; this should not happen
          ((null (cdr y))
	   (wxxml-function x l r t)) ; this should not happen, too
          (t (do ((nl) (lop ext-lop op)
                  (rop op (if (null (cdr y)) ext-rop op)))
                 ((null (cdr y))
                  (setq nl (nconc nl (wxxml (car y) l r lop rop))) nl)
	       (setq nl (nconc nl (wxxml (car y)  l (list sym)   lop rop))
		     y (cdr y)
		     l nil))))))

(defun wxxml-nofix (x l r) (wxxml (caar x) l r (caar x) rop))

(defun wxxml-matchfix (x l r)
  (setq l (append l (car (wxxmlsym (caar x))))
	;; car of wxxmlsym of a matchfix operator is the lead op
	r (append (cdr (wxxmlsym (caar x))) r)
	;; cdr is the trailing op
	x (wxxml-list (cdr x) nil r "<t>,</t>"))
  (append l x))

(defun wxxmlsym (x)
  (or (get x 'wxxmlsym)
      (get x 'strsym)
      (get x 'dissym)
      (stripdollar x)))

(defun wxxmlword (x)
  (or (get x 'wxxmlword)
      (stripdollar x)))

(defprop bigfloat wxxml-bigfloat wxxml)

;;(defun mathml-bigfloat (x l r) (declare (ignore l r)) (fpformat x))
(defun wxxml-bigfloat (x l r)
  (append l '("<n>") (fpformat x) '("</n>") r))

(defprop mprog  "<t>block</t>" wxxmlword)
(defprop %erf   "<t>erf</t>"   wxxmlword)
(defprop $erf   "<t>erf</t>"   wxxmlword)
(defprop $true  "<t>true</t>"  wxxmlword)
(defprop $false "<t>false</t>" wxxmlword)

(defprop mprogn wxxml-matchfix wxxml)
(defprop mprogn (("<p>") "</p>") wxxmlsym)

(defprop mlist wxxml-matchfix wxxml)
(defprop mlist (("<t>[</t>")"<t>]</t>") wxxmlsym)

(defprop $set wxxml-matchfix wxxml)
(defprop $set (("<t>{</t>")"<t>}</t>") wxxmlsym)

(defprop mabs wxxml-matchfix wxxml)
(defprop mabs (("<a>")"</a>") wxxmlsym)

(defprop mbox wxxml-mbox wxxml)
(defprop mlabox wxxml-mbox wxxml)

(defun wxxml-mbox (x l r)
  (setq l (wxxml (cadr x) (append l '("<hl>")) nil 'mparen 'mparen)
        r (append '("</hl>") r))
  (append l r))

(defprop mqapply wxxml-mqapply wxxml)

(defun wxxml-mqapply (x l r)
  (setq l (wxxml (cadr x) (append l '("<fn>"))
                 (list "<p>" ) lop 'mfunction)
	r (wxxml-list (cddr x) nil (cons "</p></fn>" r) "<t>,</t>"))
  (append l r))


(defprop $zeta "<g>zeta</g>" wxxmlword)
(defprop %zeta "<g>zeta</g>" wxxmlword)

;;
;; Greek characters
;;
(defprop $%alpha "<g>%alpha</g>" wxxmlword)
(defprop $%beta "<g>%beta</g>" wxxmlword)
(defprop $%gamma "<g>%gamma</g>" wxxmlword)
(defprop $%delta "<g>%delta</g>" wxxmlword)
(defprop $%epsilon "<g>%epsilon</g>" wxxmlword)
(defprop $%zeta "<g>%zeta</g>" wxxmlword)
(defprop $%eta "<g>%eta</g>" wxxmlword)
(defprop $%theta "<g>%theta</g>" wxxmlword)
(defprop $%iota "<g>%iota</g>" wxxmlword)
(defprop $%kappa "<g>%kappa</g>" wxxmlword)
(defprop $%lambda "<g>%lambda</g>" wxxmlword)
(defprop $%mu "<g>%mu</g>" wxxmlword)
(defprop $%nu "<g>%nu</g>" wxxmlword)
(defprop $%xi "<g>%xi</g>" wxxmlword)
(defprop $%omicron "<g>%omicron</g>" wxxmlword)
(defprop $%pi "<s>%pi</s>" wxxmlword)
(defprop $%rho "<g>%rho</g>" wxxmlword)
(defprop $%sigma "<g>%sigma</g>" wxxmlword)
(defprop $%tau "<g>%tau</g>" wxxmlword)
(defprop $%upsilon "<g>%upsilon</g>" wxxmlword)
(defprop $%phi "<g>%phi</g>" wxxmlword)
(defprop $%chi "<g>%chi</g>" wxxmlword)
(defprop $%psi "<g>%psi</g>" wxxmlword)
(defprop $%omega "<g>%omega</g>" wxxmlword)
(defprop |$%Alpha| "<g>%Alpha</g>" wxxmlword)
(defprop |$%Beta| "<g>%Beta</g>" wxxmlword)
(defprop |$%Gamma| "<g>%Gamma</g>" wxxmlword)
(defprop |$%Delta| "<g>%Delta</g>" wxxmlword)
(defprop |$%Epsilon| "<g>%Epsilon</g>" wxxmlword)
(defprop |$%Zeta| "<g>%Zeta</g>" wxxmlword)
(defprop |$%Eta| "<g>%Eta</g>" wxxmlword)
(defprop |$%Theta| "<g>%Theta</g>" wxxmlword)
(defprop |$%Iota| "<g>%Iota</g>" wxxmlword)
(defprop |$%Kappa| "<g>%Kappa</g>" wxxmlword)
(defprop |$%Lambda| "<g>%Lambda</g>" wxxmlword)
(defprop |$%Mu| "<g>%Mu</g>" wxxmlword)
(defprop |$%Nu| "<g>%Nu</g>" wxxmlword)
(defprop |$%Xi| "<g>%Xi</g>" wxxmlword)
(defprop |$%Omicron| "<g>%Omicron</g>" wxxmlword)
(defprop |$%Rho| "<g>%Rho</g>" wxxmlword)
(defprop |$%Sigma| "<g>%Sigma</g>" wxxmlword)
(defprop |$%Tau| "<g>%Tau</g>" wxxmlword)
(defprop |$%Upsilon| "<g>%Upsilon</g>" wxxmlword)
(defprop |$%Phi| "<g>%Phi</g>" wxxmlword)
(defprop |$%Chi| "<g>%Chi</g>" wxxmlword)
(defprop |$%Psi| "<g>%Psi</g>" wxxmlword)
(defprop |$%Omega| "<g>%Omega</g>" wxxmlword)
(defprop |$%Pi| "<g>%Pi</g>" wxxmlword)

(defprop $%i "<s>%i</s>" wxxmlword)
(defprop $%e "<s>%e</s>" wxxmlword)
(defprop $inf "<s>inf</s>" wxxmlword)
(defprop $minf "<t>-</t><s>inf</s>" wxxmlword)

(defprop mreturn "return" wxxmlword)

(defprop mquote wxxml-prefix wxxml)
(defprop mquote ("<t>'</t>") wxxmlsym)
(defprop mquote "<t>'</t>" wxxmlword)
(defprop mquote 201. wxxml-rbp)

(defprop msetq wxxml-infix wxxml)
(defprop msetq ("<t>:</t>") wxxmlsym)
(defprop msetq "<t>:</t>" wxxmlword)
(defprop msetq 180. wxxml-rbp)
(defprop msetq 20. wxxml-rbp)

(defprop mset wxxml-infix wxxml)
(defprop mset ("<t>::</t>") wxxmlsym)
(defprop mset "<t>::</t>" wxxmlword)
(defprop mset 180. wxxml-lbp)
(defprop mset 20. wxxml-rbp)

(defprop mdefine wxxml-infix wxxml)
(defprop mdefine ("<t>:=</t>") wxxmlsym)
(defprop mdefine "<t>:=</t>" wxxmlword)
(defprop mdefine 180. wxxml-lbp)
(defprop mdefine 20. wxxml-rbp)

(defprop mdefmacro wxxml-infix wxxml)
(defprop mdefmacro ("<t>::=</t>") wxxmlsym)
(defprop mdefmacro "<t>::=</t>" wxxmlword)
(defprop mdefmacro 180. wxxml-lbp)
(defprop mdefmacro 20. wxxml-rbp)

(defprop marrow wxxml-infix wxxml)
(defprop marrow ("<t>-></t>") wxxmlsym)
(defprop marrow "<t>-></t>" wxxmlword)
(defprop marrow 25 wxxml-lbp)
(defprop marrow 25 wxxml-rbp)

(defprop mfactorial wxxml-postfix wxxml)
(defprop mfactorial ("<t>!</t>") wxxmlsym)
(defprop mfactorial "<t>!</t>" wxxmlword)
(defprop mfactorial 160. wxxml-lbp)

(defprop mexpt wxxml-mexpt wxxml)
(defprop mexpt 140. wxxml-lbp)
(defprop mexpt 139. wxxml-rbp)

(defprop %sum 90. wxxml-rbp)
(defprop %product 95. wxxml-rbp)

;; insert left-angle-brackets for mncexpt. a^<t> is how a^^n looks.
(defun wxxml-mexpt (x l r)
  (let((nc (eq (caar x) 'mncexpt)))
    (setq l (wxxml (cadr x) (append l (if nc
                                          '("<e mat=\"true\"><r>")
					  '("<e><r>")))
                   nil lop (caar x))
          r (if (mmminusp (setq x (nformat (caddr x))))
                ;; the change in base-line makes parens unnecessary
                (wxxml (cadr x) '("</r><r>-")
                       (cons "</r></e>" r) 'mparen 'mparen)
		(if (and (integerp x) (< x 10))
		    (wxxml x (list "</r>")
			   (cons "</e>" r) 'mparen 'mparen)
		    (wxxml x (list "</r><r>")
			   (cons "</r></e>" r) 'mparen 'mparen)
		    )))
    (append l r)))

(defprop mncexpt wxxml-mexpt wxxml)

(defprop mncexpt 135. wxxml-lbp)
(defprop mncexpt 134. wxxml-rbp)

(defprop mnctimes wxxml-nary wxxml)
(defprop mnctimes "<t>.</t>" wxxmlsym)
(defprop mnctimes "<t>.</t>" wxxmlword)
(defprop mnctimes 110. wxxml-lbp)
(defprop mnctimes 109. wxxml-rbp)

(defprop mtimes wxxml-nary wxxml)
(defprop mtimes "<h>*</h>" wxxmlsym)
(defprop mtimes "<t>*</t>" wxxmlword)
(defprop mtimes 120. wxxml-lbp)
(defprop mtimes 120. wxxml-rbp)

(defprop %sqrt wxxml-sqrt wxxml)

(defun wxxml-sqrt (x l r)
  (wxxml (cadr x) (append l  '("<q>"))
         (append '("</q>") r) 'mparen 'mparen))

(defprop mquotient wxxml-mquotient wxxml)
(defprop mquotient ("<t>/</t>") wxxmlsym)
(defprop mquotient "<t>/</t>" wxxmlword)
(defprop mquotient 122. wxxml-lbp) ;;dunno about this
(defprop mquotient 123. wxxml-rbp)

(defun wxxml-mquotient (x l r)
  (if (or (null (cddr x)) (cdddr x)) (wna-err (caar x)))
  (setq l (wxxml (cadr x) (append l '("<f><r>")) nil 'mparen 'mparen)
	r (wxxml (caddr x) (list "</r><r>")
                 (append '("</r></f>")r) 'mparen 'mparen))
  (append l r))

(defprop $matrix wxxml-matrix wxxml)

(defun wxxml-matrix(x l r) ;;matrix looks like ((mmatrix)((mlist) a b) ...)
  (cond ((null (cdr x))
         (append l `("<fn><t>matrix</t><p/></fn>") r))
        ((and (null (cddr x))
              (null (cdadr x)))
         (append l `("<fn><t>matrix</t><p><t>[</t><t>]</t></p></fn>") r))
        (t
         (append l `("<tb>")
                 (mapcan #'(lambda (y)
			     (cond ((null (cdr y))
				    (list "<mtr><mtd><mspace/></mtd></mtr>"))
				   (t
				    (wxxml-list (cdr y)
						(list "<mtr><mtd>")
						(list "</mtd></mtr>")
						"</mtd><mtd>"))))
                         (cdr x))
                 `("</tb>") r))))

;; macsyma sum or prod is over integer range, not  low <= index <= high
;; wxxml is lots more flexible .. but

(defprop %sum wxxml-sum wxxml)
(defprop %lsum wxxml-lsum wxxml)
(defprop %product wxxml-sum wxxml)

;; easily extended to union, intersect, otherops

(defun wxxml-lsum(x l r)
  (let ((op (cond ((eq (caar x) '%lsum) "<sm><r>")))
	;; gotta be one of those above
	(s1 (wxxml (cadr x) nil nil 'mparen rop));; summand
	(index ;; "index = lowerlimit"
         (wxxml `((min simp) , (caddr x), (cadddr x))
                nil nil 'mparen 'mparen)))
    (append l `(,op ,@index
		"</r><r><mn/></r><r>"
		,@s1 "</r></sm>") r)))

(defun wxxml-sum(x l r)
  (let ((op (cond ((eq (caar x) '%sum) "<sm><r>")
		  ((eq (caar x) '%product) "<sm type=\"prod\"><r>")
                  ;; extend here
		  ))
	;; gotta be one of those above
	(s1 (wxxml (cadr x) nil nil 'mparen rop));; summand
	(index ;; "index = lowerlimit"
         (wxxml `((mequal simp) ,(caddr x) ,(cadddr x))
                nil nil 'mparen 'mparen))
	(toplim (wxxml (car (cddddr x)) nil nil 'mparen 'mparen)))
    (append l `( ,op ,@index "</r><r>" ,@toplim
		"</r><r>"
		,@s1 "</r></sm>") r)))

(defprop %integrate wxxml-int wxxml)

(defun wxxml-int (x l r)
  (let ((s1 (wxxml (cadr x) nil nil 'mparen 'mparen));;integrand delims / & d
	(var (wxxml (caddr x) nil nil 'mparen rop))) ;; variable
    (cond ((= (length x) 3)
           (append l `("<in def=\"false\"><r>"
                       ,@s1
                       "</r><r><s>d</s>"
                       ,@var
                       "</r></in>") r))
          (t ;; presumably length 5
           (let ((low (wxxml (nth 3 x) nil nil 'mparen 'mparen))
                 ;; 1st item is 0
                 (hi (wxxml (nth 4 x) nil nil 'mparen 'mparen)))
             (append l `("<in><r>"
                         ,@low
                         "</r><r>"
                         ,@hi
                         "</r><r>"
                         ,@s1
                         "</r><r><s>d</s>"
                         ,@var "</r></in>") r))))))

(defprop %limit wxxml-limit wxxml)

(defprop mrarr wxxml-infix wxxml)
(defprop mrarr ("<t>-></t>") wxxmlsym)
(defprop mrarr 80. wxxml-lbp)
(defprop mrarr 80. wxxml-rbp)

(defun wxxml-limit (x l r) ;; ignoring direction, last optional arg to limit
  (let ((s1 (wxxml (second x) nil nil 'mparen rop));; limitfunction
	(subfun ;; the thing underneath "limit"
         (wxxml `((mrarr simp) ,(third x)
                  ,(fourth x)) nil nil 'mparen 'mparen)))
    (append l `("<lm><t>lim</t><r>"
                ,@subfun "</r><r>"
                ,@s1 "</r></lm>") r)))

(defprop %at wxxml-at wxxml)
;; e.g.  at(diff(f(x)),x=a)
(defun wxxml-at (x l r)
  (let ((s1 (wxxml (cadr x) nil nil lop rop))
	(sub (wxxml (caddr x) nil nil 'mparen 'mparen)))
    (append l '("<at><r>") s1
            '("</r><r>") sub '("</r></at>") r)))

;;binomial coefficients

(defprop %binomial wxxml-choose wxxml)


(defun wxxml-choose (x l r)
  `(,@l
    "<p print=\"no\"><f line=\"no\"><r>"
    ,@(wxxml (cadr x) nil nil 'mparen 'mparen)
    "</r><r>"
    ,@(wxxml (caddr x) nil nil 'mparen 'mparen)
    "</r></f></p>"
    ,@r))


(defprop rat wxxml-rat wxxml)
(defprop rat 120. wxxml-lbp)
(defprop rat 121. wxxml-rbp)
(defun wxxml-rat(x l r) (wxxml-mquotient x l r))

(defprop mplus wxxml-mplus wxxml)
(defprop mplus 100. wxxml-lbp)
(defprop mplus 100. wxxml-rbp)

(defun wxxml-mplus (x l r)
  (cond ((memq 'trunc (car x))(setq r (cons "<t>+</t><t>...</t>" r))))
  (cond ((null (cddr x))
         (if (null (cdr x))
             (wxxml-function x l r t)
	     (wxxml (cadr x) l r 'mplus rop)))
        (t (setq l (wxxml (cadr x) l nil lop 'mplus)
                 x (cddr x))
           (do ((nl l)  (dissym))
               ((null (cdr x))
                (if (mmminusp (car x)) (setq l (cadar x) dissym
                                             (list "<t>-</t>"))
		    (setq l (car x) dissym (list "<t>+</t>")))
                (setq r (wxxml l dissym r 'mplus rop))
                (append nl r))
	     (if (mmminusp (car x)) (setq l (cadar x) dissym
					  (list "<t>-</t>"))
                 (setq l (car x) dissym (list "<t>+</t>")))
	     (setq nl (append nl (wxxml l dissym nil 'mplus 'mplus))
		   x (cdr x))))))

(defprop mminus wxxml-prefix wxxml)
(defprop mminus ("-") wxxmlsym)
(defprop mminus "<t>-</t>" wxxmlword)
(defprop mminus 100. wxxml-rbp)
(defprop mminus 100. wxxml-lbp)

(defprop $~ wxxml-infix wxxml)
(defprop $~ ("<t>~</t>") wxxmlsym)
(defprop $~ "<t>~</t>" wxxmlword)
(defprop $~ 134. wxxml-lbp)
(defprop $~ 133. wxxml-rbp)

(defprop min wxxml-infix wxxml)
(defprop min ("<t>in</t>") wxxmlsym)
(defprop min "<t>in</t>" wxxmlword)
(defprop min 80. wxxml-lbp)
(defprop min 80. wxxml-rbp)

(defprop mequal wxxml-infix wxxml)
(defprop mequal ("<t>=</t>") wxxmlsym)
(defprop mequal "<t>=</t>" wxxmlword)
(defprop mequal 80. wxxml-lbp)
(defprop mequal 80. wxxml-rbp)

(defprop mnotequal wxxml-infix wxxml)
(defprop mnotequal 80. wxxml-lbp)
(defprop mnotequal 80. wxxml-rbp)

(defprop mgreaterp wxxml-infix wxxml)
(defprop mgreaterp ("<t>&gt;</t>") wxxmlsym)
(defprop mgreaterp "<t>&gt;</t>" wxxmlword)
(defprop mgreaterp 80. wxxml-lbp)
(defprop mgreaterp 80. wxxml-rbp)

(defprop mgeqp wxxml-infix wxxml)
(defprop mgeqp ("<t>&gt;=</t>") wxxmlsym)
(defprop mgeqp "<t>&gt;=</t>" wxxmlword)
(defprop mgeqp 80. wxxml-lbp)
(defprop mgeqp 80. wxxml-rbp)

(defprop mlessp wxxml-infix wxxml)
(defprop mlessp ("<t>&lt;</t>") wxxmlsym)
(defprop mlessp "<t>&lt;</t>" wxxmlword)
(defprop mlessp 80. wxxml-lbp)
(defprop mlessp 80. wxxml-rbp)

(defprop mleqp wxxml-infix wxxml)
(defprop mleqp ("<t>&lt;=</t>") wxxmlsym)
(defprop mleqp "<t>&lt;=</t>" wxxmlword)
(defprop mleqp 80. wxxml-lbp)
(defprop mleqp 80. wxxml-rbp)

(defprop mnot wxxml-prefix wxxml)
(defprop mnot ("<t>not</t>") wxxmlsym)
(defprop mnot "<t>not</t>" wxxmlword)
(defprop mnot 70. wxxml-rbp)

(defprop mand wxxml-nary wxxml)
(defprop mand "<mspace/><t>and</t><mspace/>" wxxmlsym)
(defprop mand "<t>and</t>" wxxmlword)
(defprop mand 60. wxxml-lbp)
(defprop mand 60. wxxml-rbp)

(defprop mor wxxml-nary wxxml)
(defprop mor "<mspace/><t>or</t><mspace/>" wxxmlsym)
(defprop mor "<t>or</t>" wxxmlword)
(defprop mor 50. wxxml-lbp)
(defprop mor 50. wxxml-rbp)


(defun wxxml-setup (x)
  (let((a (car x))
       (b (cadr x)))
    ;;      (setf (get a 'wxxml) 'wxxml-prefix) ; we don't want sin x
    (setf (get a 'wxxmlword) b)
    (setf (get a 'wxxmlsym) (list b))
    (setf (get a 'wxxml-rbp) 320)
    (setf (get a 'wxxml-lbp) 320)))


(mapc #'wxxml-setup
      '(
        (%acos "<v>acos</v>")
        (%asin "<v>asin</v>")
        (%asinh "<v>asinh</v>")
        (%acosh "<v>acosh</v>")
        (%atan "<v>atan</v>")
        (%atanh "<v>atanh</v>")
        (%arg "<v>arg</v>")
        (%bessel_j "<v>bessel_j</v>")
        (%bessel_i "<v>bessel_i</v>")
        (%bessel_k "<v>bessel_k</v>")
        (%bessel_y "<v>bessel_y</v>")
        (%beta "<v>beta</v>")
        (%cos "<v>cos</v>")
        (%cosh "<v>cosh</v>")
        (%cot "<v>cot</v>")
        (%coth "<v>coth</v>")
        (%csc "<v>csc</v>")
        (%deg "<v>deg</v>")
        (%determinant "<v>determinant</v>")
        (%dim "<v>dim</v>")
        (%exp "<v>exp</v>")
        (%gamma "<g>gamma</g>")
        (%gcd "<v>gcd</v>")
        (%hom "<v>hom</v>")
        (%ker "<v>ker</v>")
        (%lg "<v>lg</v>")
        (%liminf "<v>lim inf</v>")
        (%limsup "<v>lim sup</v>")
        (%ln "<v>ln</v>")
        ($li "<v>li</v>")
        (%log "<v>log</v>")
        (%max "<v>max</v>")
        (%min "<v>min</v>")
        ($min "<v>min</v>")
        ($psi "<v>psi</v>")
        (%sec "<v>sec</v>")
        (%sech "<v>sech</v>")
        (%sin "<v>sin</v>")
        (%sinh "<v>sinh</v>")
        (%sup "<v>sup</v>")
        (%tan "<v>tan</v>")
        (%tanh "<v>tanh</v>")
        (%erf "<v>erf</v>")
        (%laplace "<v>laplace</v>")
        ))

(defprop mcond wxxml-mcond wxxml)
(defprop mcond 25. wxxml-lbp)
(defprop mcond 25. wxxml-rbp)

(defprop %derivative wxxml-derivative wxxml)
(defprop %derivative 120. wxxml-lbp)
(defprop %derivative 119. wxxml-rbp)

(defun wxxml-derivative (x l r)
  (wxxml (wxxml-d x "<s>d</s>") (append l '("<d>"))
         (append '("</d>") r) 'mparen 'mparen))

(defun wxxml-d (x dsym) ;dsym should be "&DifferentialD;" or "&PartialD;"
  ;; format the macsyma derivative form so it looks
  ;; sort of like a quotient times the deriva-dand.
  (let*
      (($simp t)
       (arg (cadr x)) ;; the function being differentiated
       (difflist (cddr x)) ;; list of derivs e.g. (x 1 y 2)
       (ords (odds difflist 0)) ;; e.g. (1 2)
       (ords (cond ((null ords) '(1))
                   (t ords)))
       (vars (odds difflist 1)) ;; e.g. (x y)
       (numer `((mexpt) ,dsym ((mplus) ,@ords))) ; d^n numerator
       (denom (cons '(mtimes)
                    (mapcan #'(lambda(b e)
                                `(,dsym ,(simplifya `((mexpt) ,b ,e) nil)))
                            vars ords))))
    `((mtimes)
      ((mquotient) ,(simplifya numer nil) ,denom)
      ,arg)))

;;(defun wxxml-mcond (x l r)
;;  (append l
;;          (wxxml (cadr x) '("<t>if</t><mspace/>")
;;                 '("<mspace/><t>then</t><mspace/>") 'mparen 'mparen)
;;          (if (eql (fifth x) '$false)
;;              (wxxml (caddr x) nil r 'mcond rop)
;;            (append (wxxml (caddr x) nil nil 'mparen 'mparen)
;;                    (wxxml (fifth x) '("<mspace/><t>else</t><mspace/>")
;;                           r 'mcond rop)))))
(defun wxxml-mcond (x l r)
  (let ((res ()))
    (setq res (wxxml (cadr x) '("<t>if</t><mspace/>")
		     '("<mspace/><t>then</t><mspace/>") 'mparen 'mparen))
    (setq res (append res (wxxml (caddr x) nil
				 '("<mspace/>") 'mparen 'mparen)))
    (let ((args (cdddr x)))
      (loop while (>= (length args) 2) do
	    (cond
	      ((and (= (length args) 2) (eql (car args) t))
	       (unless (or (eql (cadr args) '$false) (null (cadr args)))
		 (setq res (wxxml (cadr args)
				  (append res '("<t>else</t><mspace/>"))
				  nil 'mparen 'mparen))))
	      (t
	       (setq res (wxxml (car args)
				(append res '("<t>elseif</t><mspace/>"))
				(wxxml (cadr args)
				       '("<mspace/><t>then</t><mspace/>")
				       '("<mspace/>") 'mparen 'mparen)
				'mparen 'mparen))))
	    (setq args (cddr args)))
      (append l res r))))

(defprop mdo wxxml-mdo wxxml)
(defprop mdo 30. wxxml-lbp)
(defprop mdo 30. wxxml-rbp)
(defprop mdoin wxxml-mdoin wxxml)
(defprop mdoin 30. wxxml-rbp)

(defun wxxml-lbp (x)
  (cond ((get x 'wxxml-lbp))
        (t(lbp x))))

(defun wxxml-rbp (x)
  (cond ((get x 'wxxml-rbp))
        (t(lbp x))))

;; these aren't quite right

(defun wxxml-mdo (x l r)
  (wxxml-list (wxxmlmdo x) l r "<mspace/>"))

(defun wxxml-mdoin (x l r)
  (wxxml-list (wxxmlmdoin x) l r "<mspace/>"))

(defun wxxmlmdo (x)
  (nconc (cond ((second x) `("<t>for</t>" ,(second x))))
	 (cond ((equal 1 (third x)) nil)
	       ((third x)  `("<t>from</t>" ,(third x))))
	 (cond ((equal 1 (fourth x)) nil)
	       ((fourth x) `("<t>step</t>" ,(fourth x)))
	       ((fifth x)  `("<t>next</t>" ,(fifth x))))
	 (cond ((sixth x)  `("<t>thru</t>" ,(sixth x))))
	 (cond ((null (seventh x)) nil)
	       ((eq 'mnot (caar (seventh x)))
		`("<t>while</t>" ,(cadr (seventh x))))
	       (t `("<t>unless</t>" ,(seventh x))))
	 `("<t>do</t>" ,(eighth x))))

(defun wxxmlmdoin (x)
  (nconc `("<t>for</t>" ,(second x) "<t>in</t>"
           ,(third x))
	 (cond ((sixth x) `("<t>thru</t>" ,(sixth x))))
	 (cond ((null (seventh x)) nil)
	       ((eq 'mnot (caar (seventh x)))
		`("<t>while</t>" ,(cadr (seventh x))))
	       (t `("<t>unless</t>" ,(seventh x))))
	 `("<t>do</t>" ,(eighth x))))


(defun wxxml-matchfix-np (x l r)
  (setq l (append l (car (wxxmlsym (caar x))))
	;; car of wxxmlsym of a matchfix operator is the lead op
	r (append (cdr (wxxmlsym (caar x))) r)
	;; cdr is the trailing op
	x (wxxml-list (cdr x) nil r ""))
  (append l x))

(defprop text-string wxxml-matchfix-np wxxml)
(defprop text-string (("<t>")"</t>") wxxmlsym)

(defprop mtext wxxml-matchfix-np wxxml)
(defprop mtext (("")"") wxxmlsym)

(defun wxxml-mlable (x l r)
  (wxxml (caddr x)
         (append l
                 (if (cadr x)
                     (list
		      (format nil "<lbl>(~A) </lbl>"
			      (stripdollar (maybe-invert-string-case (symbol-name (cadr x))))))
		     nil))
         r 'mparen 'mparen))

(defprop mlable wxxml-mlable wxxml)

(defun wxxml-spaceout (x l r)
  (append l (list " " (make-string (cadr x) :initial-element #\.) "") r))

(defprop spaceout wxxml-spaceout wxxml)

(defun mydispla (x)
  (let ((ccol 1)
        (texport *standard-output*))
    (mapc #'princ
          (wxxml x '("<mth>") '("</mth>") 'mparen 'mparen))))

(setf *alt-display2d* 'mydispla)

(defun $set_display (tp)
  (cond
    ((eq tp '$none)
     (setq $display2d nil))
    ((eq tp '$ascii)
     (setq $display2d t)
     (setf *alt-display2d* nil))
    ((eq tp '$xml)
     (setq $display2d t)
     (setf *alt-display2d* 'mydispla))
    (t
     (format t "Unknown display type")
     (setq tp '$unknown)))
  tp)

;;;
;;; This is the display support only - copy/paste will not work
;;;

(defmvar $pdiff_uses_prime_for_derivatives nil)
(defmvar $pdiff_prime_limit 3)
(defmvar $pdiff_uses_named_subscripts_for_derivatives nil)
(defmvar $pdiff_diff_var_names (list '(mlist) '|$x| '|$y| '|$z|))

(setf (get '%pderivop 'wxxml) 'wxxml-pderivop)

(defun wxxml-pderivop (x l r)
  (cond ((and $pdiff_uses_prime_for_derivatives (eq 3 (length x)))
	 (let* ((n (car (last x)))
		(p))
	   
	   (cond ((<= n $pdiff_prime_limit)
		  (setq p (make-list n :initial-element "'")))
		 (t
		  (setq p (list "(" n ")"))))
	   (cond ((eq rop 'mexpt)
		  (append l (list "<p><e><r>")
                          (wxxml (cadr x) nil nil lop rop)
			  (list "</r><r>") p
                          (list "</r></e>") (list "</p>") r))
		 (t
		  (append (append l '("<e><r>"))
                          (wxxml (cadr x) nil nil lop rop)
			  (list "</r><r>") p
                          (list "</r></e>")  r)))))
	
	((and $pdiff_uses_named_subscripts_for_derivatives
	      (< (apply #'+ (cddr x)) $pdiff_prime_limit))
	 (let ((n (cddr x))
	       (v (mapcar #'stripdollar (cdr $pdiff_diff_var_names)))
	       (p))
	   (cond ((> (length n) (length v))
		  (merror "Not enough elements in pdiff_diff_var_names to display the expression")))
	   (dotimes (i (length n))
	     (setq p (append p (make-list (nth i n)
                                          :initial-element (nth i v)))))
	   (append (append l '("<i><r>"))
                   (wxxml (cadr x) nil nil lop rop)
                   (list "</r><r>") p (list "</r></i>") r)))
	(t
	 (append (append l '("<i><r>"))
                 (wxxml (cadr x) nil nil lop rop)
                 (list "</r><r>(")
		 (wxxml-list (cddr x) nil nil ",")
                 (list ")</r></i>") r))))


;;
;; Port of Barton Willis's texput function.
;;

(defun $wxxmlput (e s &optional tx lbp rbp)
  (cond ((mstringp e)
	 (setq e (define-symbol (string-left-trim '(#\&) e)))))
  (cond (($listp s)
	 (setq s (margs s)))
	(t
	 (setq s (list s))))
  (setq s (mapcar #'wxxml-stripdollar s))
  (cond ((or (null lbp) (not (integerp lbp)))
         (setq lbp 180)))
  (cond ((or (null rbp) (not (integerp rbp)))
         (setq rbp 180)))
  (cond ((null tx)
	 (putprop e (nth 0 s) 'wxxmlword))
	((eq tx '$matchfix)
	 (putprop e 'wxxml-matchfix 'wxxml)
	 (cond ((< (length s) 2)
		(merror
		 "Improper 2nd argument to `wxxmlput' for matchfix operator."))
	       ((eq (length s) 2)
		(putprop e (list (list (nth 0 s)) (nth 1 s)) 'wxxmlsym))
	       (t
		(putprop
		 e (list (list (nth 0 s)) (nth 1 s) (nth 2 s)) 'wxxmlsym))))
	((eq tx '$prefix)
	 (putprop e 'wxxml-prefix 'wxxml)
	 (putprop e s 'wxxmlsym)
         (putprop e lbp 'wxxml-lbp)
         (putprop e rbp 'wxxml-rbp))
	((eq tx '$infix)
	 (putprop e 'wxxml-infix 'wxxml)
	 (putprop e  s 'wxxmlsym)
         (putprop e lbp 'wxxml-lbp)
         (putprop e rbp 'wxxml-rbp))
	((eq tx '$postfix)
	 (putprop e 'wxxml-postfix 'wxxml)
	 (putprop e  s 'wxxmlsym)
         (putprop e lbp 'wxxml-lbp))
        (t (merror "Improper arguments to `wxxmlput'."))))
