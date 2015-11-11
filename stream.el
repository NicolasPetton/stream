;;; stream.el --- Implementation of streams  -*- lexical-binding: t -*-

;; Copyright (C) 2015 Free Software Foundation, Inc.

;; Author: Nicolas Petton <nicolas@petton.fr>
;; Keywords: stream, laziness, sequences
;; Version: 2.1.0
;; Package-Requires: ((emacs "25"))
;; Package: stream

;; Maintainer: nicolas@petton.fr

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library provides an implementation of streams. Streams are
;; implemented as delayed evaluation of cons cells.
;;
;; Functions defined in `seq.el' can also take a stream as input.
;;
;; streams could be created from any sequential input data:
;; - sequences, making operation on them lazy
;; - a set of 2 forms (first and rest), making it easy to represent infinite sequences
;; - buffers (by character)
;; - buffers (by line)
;; - buffers (by page)
;; - IO streams
;; - orgmode table cells
;; - ...
;;
;; All functions are prefixed with "stream-".
;; All functions are tested in test/automated/stream-tests.el
;;
;; Here is an example implementation of the Fibonacci numbers
;; implemented as in infinite stream:
;;
;; (defun fib (a b)
;;  (stream-cons a (fib b (+ a b))))
;; (fib 0 1)

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'seq)
(require 'thunk)

(eval-and-compile
  (defconst stream--identifier '--stream--
    "Symbol internally used to identify streams."))

(defmacro stream-make (&rest body)
  "Return a stream built from BODY.
BODY must return nil or a cons cell whose cdr is itself a
stream."
  (declare (debug t))
  `(list ',stream--identifier (thunk-delay ,@body)))

(defmacro stream-cons (first rest)
  "Return a stream built from the cons of FIRST and REST.
FIRST and REST are forms and REST must return a stream."
  (declare (debug t))
  `(stream-make (cons ,first ,rest)))


;;; Convenient functions for creating streams

(cl-defgeneric stream (src)
  "Return a new stream from SRC.")

(cl-defmethod stream ((seq sequence))
  "Return a stream built from the sequence SEQ.
SEQ can be a list, vector or string."
  (if (seq-empty-p seq)
      (stream-empty)
    (stream-cons
     (seq-elt seq 0)
     (stream (seq-subseq seq 1)))))

(cl-defmethod stream ((list list))
  "Return a stream built from the list LIST."
  (if (null list)
      (stream-empty)
    (stream-cons
     (car list)
     (stream (cdr list)))))

(cl-defmethod stream ((buffer buffer) &optional pos)
  "Return a stream of the characters of the buffer BUFFER.
BUFFER may be a buffer or a string (buffer name).
The sequence starts at POS if non-nil, 1 otherwise."
  (with-current-buffer buffer
    (unless pos (setq pos (point-min)))
    (if (>= pos (point-max))
        (stream-empty))
    (stream-cons
     (with-current-buffer buffer
       (save-excursion
         (save-restriction
           (widen)
           (goto-char pos)
           (char-after (point)))))
     (stream buffer (1+ pos)))))

(defun stream-regexp (buffer regexp)
  (stream-make
   (let (match)
     (with-current-buffer buffer
       (setq match (re-search-forward regexp nil t)))
     (when match
       (cons (match-data) (stream-regexp buffer regexp))))))

(defun stream-range (&optional start end step)
  "Return a stream of the integers from START to END, stepping by STEP.
If START is nil, it defaults to 0. If STEP is nil, it defaults to
1.  START is inclusive and END is exclusive.  If END is nil, the
range is infinite."
  (unless start (setq start 0))
  (unless step (setq step 1))
  (if (equal start end)
      (stream-empty)
    (stream-cons
     start
     (stream-range (+ start step) end step))))


(defun streamp (stream)
  "Return non-nil if STREAM is a stream, nil otherwise."
  (and (consp stream)
       (eq (car stream) stream--identifier)))

(defun stream-empty ()
  "Return an empty stream."
  (list stream--identifier (thunk-delay nil)))

(defun stream-empty-p (stream)
  "Return non-nil is STREAM is empty, nil otherwise."
  (null (thunk-force (cadr stream))))

(defun stream-first (stream)
  "Return the first element of STREAM."
  (car (thunk-force (cadr stream))))

(defun stream-rest (stream)
  "Return a stream of all but the first element of STREAM."
  (or (cdr (thunk-force (cadr stream)))
      (stream-empty)))

(defmacro stream-pop (stream)
  "Return the first element of STREAM and set the value of STREAM to its rest."
  (unless (symbolp stream)
    (error "STREAM must be a symbol"))
  `(prog1
       (stream-first ,stream)
     (setq ,stream (stream-rest ,stream))))


;;; cl-generic support for streams

(cl-generic-define-generalizer stream--generalizer
  11
  (lambda (name)
    `(when (streamp ,name)
       'stream))
  (lambda (tag)
    (when (eq tag 'stream)
      '(stream))))

(cl-defmethod cl-generic-generalizers ((_specializer (eql stream)))
  "Support for `stream' specializers."
  (list stream--generalizer))


;;; Implementation of seq.el generic functions

(cl-defmethod seqp ((_stream stream))
  t)

(cl-defmethod seq-elt ((stream stream) n)
  "Return the element of STREAM at index N."
  (while (> n 0)
    (setq stream (stream-rest stream))
    (setq n (1- n)))
  (stream-first stream))

(cl-defmethod seq-length ((stream stream))
  "Return the length of STREAM.
This function will eagerly consume the entire stream."
  (let ((len 0))
    (while (not (stream-empty-p stream))
      (setq len (1+ len))
      (setq stream (stream-rest stream)))
    len))

(cl-defmethod seq-subseq ((stream stream) start end)
  (seq-take (seq-drop stream start) (- end start)))

(cl-defmethod seq-into-sequence ((stream stream))
  "Convert STREAM into a sequence."
  (let ((list))
    (seq-doseq (elt stream)
      (push elt list))
    (nreverse list)))

(cl-defmethod seq-into ((stream stream) type)
  "Convert STREAM into a sequence of type TYPE."
  (seq-into (seq-into-sequence stream) type))

(cl-defmethod seq-into ((stream stream) (_type (eql stream)))
  stream)

(cl-defmethod seq-into ((seq sequence) (_type (eql stream)))
  (stream seq))

(cl-defmethod seq-take ((stream stream) n)
  "Return a stream of the first N elements of STREAM."
  (if (or (zerop n)
          (stream-empty-p stream))
      (stream-empty)
    (stream-cons
     (stream-first stream)
     (seq-take (stream-rest stream) (1- n)))))

(cl-defmethod seq-drop ((stream stream) n)
  "Return a stream of STREAM without its first N elements."
  (stream-make
   (while (not (or (stream-empty-p stream) (zerop n)))
     (setq n (1- n))
     (setq stream (stream-rest stream)))
   (unless (stream-empty-p stream)
     (cons (stream-first stream)
           (stream-rest stream)))))

(cl-defmethod seq-take-while (pred (stream stream))
  "Return a stream of the successive elements for which (PRED elt) is non-nil in STREAM."
  (stream-make
   (when (funcall pred (stream-first stream))
     (cons (stream-first stream)
           (seq-take-while pred (stream-rest stream))))))

(cl-defmethod seq-drop-while (pred (stream stream))
  "Return a stream from the first element for which (PRED elt) is nil in STREAM."
  (stream-make
   (while (not (or (stream-empty-p stream)
                   (funcall pred (stream-first stream))))
     (setq stream (stream-rest stream)))
   (unless (stream-empty-p stream)
     (cons (stream-first stream)
           (stream-rest stream)))))

(cl-defmethod seq-map (function (stream stream))
    "Return a stream representing the mapping of FUNCTION over STREAM.
The elements of the produced stream are the results of the
applications of FUNCTION on each element of STREAM in succession."
  (stream-make
   (when (not (stream-empty-p stream))
     (cons (funcall function (stream-first stream))
           (seq-map function (stream-rest stream))))))

(cl-defmethod seq-do (function (stream stream))
  "Evaluate FUNCTION for each element of STREAM eagerly, and return nil.

`seq-do' should never be used on infinite streams without some
kind of nonlocal exit."
  (while (not (stream-empty-p stream))
    (funcall function (stream-first stream))
    (setq stream (stream-rest stream))))

(cl-defmethod seq-filter (pred (stream stream))
  "Return a stream of the elements for which (PRED element) is non-nil in STREAM."
  (if (stream-empty-p stream)
      stream
    (stream-make
     (while (not (or (stream-empty-p stream)
                     (funcall pred (stream-first stream))))
       (setq stream (stream-rest stream)))
     (if (stream-empty-p stream)
         nil
       (cons (stream-first stream)
             (seq-filter pred (stream-rest stream)))))))

(cl-defmethod seq-copy ((stream stream))
  "Return a shallow copy of STREAM."
  (stream-cons (stream-first stream)
               (stream-rest stream)))

(provide 'stream)
;;; stream.el ends here
