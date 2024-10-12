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
    ))

(defun graph (connections &key (stream T))
  (with-normalized-stream (stream stream)
    ))

(defun progress (percentage &key (stream T) (width *print-right-margin*) (label T))
  (with-normalized-stream (stream stream)
    ))

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
