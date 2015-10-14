# stream.el [![Build Status](https://secure.travis-ci.org/NicolasPetton/stream.png)](http://travis-ci.org/NicolasPetton/stream)

## Summary

`stream.el` provides an implementation of streams, defined as as delayed
evaluation of cons cells.

`stream.el` requires Emacs >= 25.1.

Functions defined in `seq.el' can also take a stream as input.

Streams could be created from any sequential input data:
 - sequences, making operation on them lazy
 - a set of 2 forms (first and rest), making it easy to represent infinite sequences
 - buffers (by character)
 - buffers (by line)
 - buffers (by page)
 - IO streams
 - orgmode table cells
 - ...

All functions are prefixed with "stream-".
All functions are tested in test/automated/stream-tests.el

Here is an example implementation of the Fibonacci numbers
implemented as in infinite stream:

    (defun fib (a b)
      (stream-cons a (fib b (+ a b))))
    (fib 0 1)

## Functions

As well as working all functions defined in seq.el, stream.el provides the
following stream-specifec functions:

- `stream` src

  This function returns a new stream from `src`.  This generic method can be
  extended, and supports out of the box lists, strings, arrays and buffers as
  input.

- `stream-cons` first rest

  This macro returns a stream built from the cons of `first` and `rest`.
`first` and `rest` are forms and `rest` must return a stream.

- `seq-make` body

  This macro returns a stream built from `body`.  `body` must return nil or a
  cons cell, which cdr is itself a stream.

## Contributing

Since this library is in GNU ELPA, contributors must have signed the Emacs
Copyright assignment.

Fetch dependencies:

    $ cd /path/to/stream.el
    $ cask

Run the tests:

    $ ./run-tests.sh

[COPYING]: ./COPYING
