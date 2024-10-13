(in-package #:org.shirakumo.text-draw)

(defmacro with-normalized-stream ((stream streamish) &body body)
  (let ((thunk (gensym "THUNK")))
    `(let ((,stream ,streamish))
       (flet ((,thunk (,stream) ,@body))
         (etypecase ,stream
           (stream (,thunk ,stream))
           ((eql T) (,thunk *standard-output*))
           (null (with-output-to-string (,stream)
                   (,thunk ,stream))))))))

(defun table (table &key (stream T) (padding 1) (borders T))
  (with-normalized-stream (stream stream)
    (let* ((columns (length (first table)))
           (widths (append (loop for i from 0 below columns
                                 collect (loop for row in table
                                               maximize (+ (* 2 padding) (length (princ-to-string (nth i row))))))
                           '(0)))
           (values (loop for row in table
                         collect (loop for value in row
                                       for width in widths
                                       collect width collect value))))
      (if borders
          (loop for row = (pop values)
                do (loop for (width val) on row by #'cddr
                         do (format stream "~v{ ~}" padding 0)
                            (format stream "~va" (- width padding padding) val)
                            (format stream "~v{ ~}" padding 0))
                   (format stream "~%")
                while values)
          (loop initially (format stream "┌~{~v{─~}~^┬~:*~}┐~%" widths)
                for row = (pop values)
                do (format stream "│")
                   (loop for (width val) on row by #'cddr
                         do (format stream "~v{ ~}" padding 0)
                            (format stream "~va" (- width padding padding) val)
                            (format stream "~v{ ~}│" padding 0))
                   (format stream "~%")
                   (when values
                     (format stream "├~{~v{─~}~^┼~:*~}┤~%" widths))
                while values
                finally (format stream "└~{~v{─~}~^┴~:*~}┘" widths))))))

(defun tree (root children-fun &key (stream T) (max-depth (or *print-level* 3)) (key #'identity))
  (with-normalized-stream (stream stream)
    (labels ((recurse (node last depth)
               (when last
                 (destructuring-bind (cur . rest) last
                   (dolist (p (reverse rest))
                     (format stream "~:[│  ~;   ~]" p))
                   (format stream "~:[├~;└~]─" cur)))
               (cond ((< depth max-depth)
                      (format stream " ~a~%" (funcall key node))
                      (let ((children (funcall children-fun node)))
                        (when (typep children 'sequence)
                          (loop with max = (1- (length children))
                                for j from 0 to max
                                do (recurse (elt children j) (list* (= max j) last) (1+ depth))))))
                     (t
                      (format stream "...~%")))))
      (recurse root () 0))))

(defun node (inputs outputs &key (stream T) label)
  (with-normalized-stream (stream stream)
    (let* ((height (max (length inputs) (length outputs)))
           (igap (truncate (- height (length inputs)) 2))
           (ogap (truncate (- height (length outputs)) 2))
           (ivlen (loop for port in inputs maximize (if (consp port) (length (princ-to-string (cdr port))) 0)))
           (iplen (loop for port in inputs maximize (if (consp port) (length (princ-to-string (car port))) (length (princ-to-string port)))))
           (ovlen (loop for port in outputs maximize (if (consp port) (length (princ-to-string (cdr port))) 0)))
           (oplen (loop for port in outputs maximize (if (consp port) (length (princ-to-string (car port))) (length (princ-to-string port)))))
           (width (+ iplen oplen (if label (+ 1 (length (princ-to-string label))) 1))))
      (format stream "~v{ ~} ┌~v{─~}┐ ~v{ ~}~%" ivlen 0 width 0 ovlen 0)
      (dotimes (i height)
        ;; Print the left hand port
        (cond ((or (< 0 igap) (null inputs))
               (format stream "~v{ ~} │~v{ ~}" ivlen 0 iplen 0)
               (decf igap))
              ((consp (car inputs))
               (destructuring-bind (port . value) (pop inputs)
                 (format stream "~v@a╶┤~va" ivlen value iplen port)))
              (T
               (format stream "~v{ ~} ┤~va" ivlen 0 iplen (pop inputs))))
        ;; Print the label
        (format stream "~v{ ~}" (- width iplen oplen) 0)
        ;; Print the right hand port
        (cond ((or (< 0 ogap) (null outputs))
               (format stream "~v{ ~}│ ~v{ ~}" oplen 0 ovlen 0)
               (decf ogap))
              ((consp (car outputs))
               (destructuring-bind (port . value) (pop outputs)
                 (format stream "~v@a├╴~va" oplen port oplen value)))
              (T
               (format stream "~v@a├ ~v{ ~}" oplen (pop outputs) ovlen 0)))
        (terpri stream))
      (format stream "~v{ ~} └~v{─~}┘ ~v{ ~}" ivlen 0 width 0 ovlen 0))))

(defun graph (connections &key (stream T))
  (with-normalized-stream (stream stream)
    ))

(defun progress (percentage &key (stream T) (width *print-right-margin*) (label T))
  (with-normalized-stream (stream stream)
    (let* ((width (or width 80))
           (bar-width (max 0 (if label (- width 5) width)))
           (full (max 0 (min bar-width (floor (* percentage 1/100 bar-width)))))
           (empty (- bar-width full)))
      (format stream "~v{█~}~v{░~}" full 0 empty 0)
      (when label (format stream " ~3d%" (floor percentage))))))

(defun wrap-char-p (char)
  (and (not (char= char #\Linefeed))
       (not (char= char #\Return))
       #+sb-unicode (sb-unicode:whitespace-p char)
       #-sb-unicode (member char '(#\Space #\Tab))))

(defun wrap (line width)
  (let ((lines ())
        (line-start 0)
        (last-candidate 0))
    (flet ((push-line (at)
             ;; Backscan AT to exclude trailing whitespace
             (loop while (and (< 1 at) (wrap-char-p (char line (1- at)))) do (decf at))
             (push (subseq line line-start at) lines)
             ;; Forwscan AT to exclude following whitespace
             (loop while (and (< at (length line)) (wrap-char-p (char line at))) do (incf at))
             (setf line-start at last-candidate at)))
      (loop for i from 0 below (length line)
            for char = (char line i)
            do (cond ((< (- i line-start) width)
                      (cond ((member char '(#\Return #\Linefeed))
                             (push-line i))
                            ((wrap-char-p char)
                             (setf last-candidate i))))
                     ((= line-start last-candidate)
                      (push-line i))
                     (T
                      (push-line last-candidate)))
            finally (when (< line-start (length line))
                      (push (subseq line line-start) lines)))
      (nreverse lines))))

(defun align (alignment line width)
  (let ((diff (- width (length line))))
    (if (<= diff 0)
        (cons 0 0)
        (ecase alignment
          ((:left) (cons 0 diff))
          ((:right) (cons diff 0))
          ((:middle :center) (cons (truncate diff 2) (- diff (truncate diff 2))))))))

(defun box (text &key (stream T) (width *print-right-margin*) (align :middle))
  (with-normalized-stream (stream stream)
    (let ((text (if (listp text) text (list text))))
      (when (or (eql T width) (null width))
        (setf width (loop for line in text maximize (+ 2 (length line)))))
      (setf text (loop for line in text
                       append (wrap line (- width 2))))
      (format stream "┌~v{─~}┐~%" (- width 2) 0)
      (dolist (line text)
        (destructuring-bind (l . r) (align align line (- width 2))
          (format stream "│~v{ ~}~a~v{ ~}│~%" l 0 line r 0)))
      (format stream "└~v{─~}┘" (- width 2) 0))))

(defun horizontal-line (width height &key (stream T) (bend :middle))
  (with-normalized-stream (stream stream)
    (when (< width 0) (setf width (- width) height (- height)))
    (let* ((l (ecase bend
                ((:left :start) 1)
                ((:right :end) (- width 2))
                ((:middle :center) (truncate width 2))))
           (r (- width l)))
      (cond ((< +1 height)
             (format stream "~v{─~}╮~v{ ~}~%" l 0 r 0)
             (dotimes (i (- height 2))
               (format stream "~v{ ~}│~v{ ~}~%" l 0 r 0))
             (format stream "~v{ ~}╰~v{─~}" l 0 r 0))
            ((< height -1)
             (format stream "~v{ ~}╭~v{─~}~%" l 0 r 0)
             (dotimes (i (- (- height) 2))
               (format stream "~v{ ~}│~v{ ~}~%" l 0 r 0))
             (format stream "~v{─~}╯~v{ ~}" l 0 r 0))
            (T
             (format stream "~v{─~}" width 0))))))

(defun vertical-line (width height &key (stream T) (bend :middle))
  (with-normalized-stream (stream stream)
    (when (< height 0) (setf width (- width) height (- height)))
    (let* ((u (ecase bend
                ((:top :start) 1)
                ((:bottom :end) (- height 2))
                ((:middle :center) (truncate height 2))))
           (b (- height u 1)))
      (cond ((< +1 width)
             (dotimes (i u)
               (format stream "│~v{ ~}~%" (- width 1) 0))
             (format stream "╰~v{─~}╮~%" (- width 2) 0)
             (dotimes (i b)
               (format stream "~v{ ~}│~%" (- width 1) 0)))
            ((< width -1)
             (dotimes (i u)
               (format stream "~v{ ~}│~%" (- (- width) 1) 0))
             (format stream "╭~v{─~}╯~%" (- (- width) 2) 0)
             (dotimes (i b)
               (format stream "│~v{ ~}~%" (- (- width) 1) 0)))
            (T
             (format stream "~v{│~^~%~}" height 0))))))

(defun line (width height &rest args)
  (if (<= (abs height) (abs width))
      (apply #'horizontal-line width height args)
      (apply #'vertical-line width height args)))
