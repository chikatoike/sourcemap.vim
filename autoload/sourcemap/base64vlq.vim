" Copyright 2012 chikatoike
" Copyright 2011 Mozilla Foundation and contributors
" Licensed under the New BSD license. See LICENSE or:
" http://opensource.org/licenses/BSD-3-Clause
"
" Based on the Base 64 VLQ implementation in Closure Compiler:
" https://code.google.com/p/closure-compiler/source/browse/trunk/src/com/google/debugging/sourcemap/Base64VLQ.java
"
" Copyright 2011 The Closure Compiler Authors. All rights reserved.
" Redistribution and use in source and binary forms, with or without
" modification, are permitted provided that the following conditions are
" met:
"
"  * Redistributions of source code must retain the above copyright
"    notice, this list of conditions and the following disclaimer.
"  * Redistributions in binary form must reproduce the above
"    copyright notice, this list of conditions and the following
"    disclaimer in the documentation and/or other materials provided
"    with the distribution.
"  * Neither the name of Google Inc. nor the names of its
"    contributors may be used to endorse or promote products derived
"    from this software without specific prior written permission.
"
" THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
" "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
" LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
" A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
" OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
" SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
" LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
" DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
" THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
" (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
" OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
let s:save_cpo = &cpo
set cpo&vim

let s:bitwise = vital#of('sourcemap').load('Bitwise').Bitwise

let s:base64vlq = {}

function! sourcemap#base64vlq#new()
  return deepcopy(s:base64vlq)
endfunction

" A single base 64 digit can contain 6 bits of data. For the base 64 variable
" length quantities we use in the source map spec, the first bit is the sign,
" the next four bits are the actual value, and the 6th bit is the
" continuation bit. The continuation bit tells us whether there are more
" digits in this value following this digit.
"
"   Continuation
"   |    Sign
"   |    |
"   V    V
"   101011

let s:VLQ_BASE_SHIFT = 5

" binary: 100000
let s:VLQ_BASE = 0x20 " 1 << s:VLQ_BASE_SHIFT

" binary: 011111
let s:VLQ_BASE_MASK = s:VLQ_BASE - 1

" binary: 100000
let s:VLQ_CONTINUATION_BIT = s:VLQ_BASE

" Converts from a two-complement value to a value where the sign bit is
" is placed in the least significant bit.  For example, as decimals:
"   1 becomes 2 (10 binary), -1 becomes 3 (11 binary)
"   2 becomes 4 (100 binary), -2 becomes 5 (101 binary)
"
function! s:toVLQSigned(aValue)
  return a:aValue < 0
        \ ? ((-a:aValue) * 2) + 1
        \ : (a:aValue * 2) + 0
endfunction

" Converts to a two-complement value from a value where the sign bit is
" is placed in the least significant bit.  For example, as decimals:
"   2 (10 binary) becomes 1, 3 (11 binary) becomes -1
"   4 (100 binary) becomes 2, 5 (101 binary) becomes -2
"
function! s:fromVLQSigned(aValue)
  let isNegative = s:bitwise.and(a:aValue, 1) == 1
  let shifted = a:aValue / 2
  return isNegative
        \ ? -shifted
        \ : shifted
endfunction

" Returns the base 64 VLQ encoded value.
"
function! s:base64vlq.encode(aValue)
  let encoded = ""
  let digit

  let vlq = s:toVLQSigned(a:aValue)

  while 1
    let digit = s:bitwise.and(vlq, s:VLQ_BASE_MASK)
    let vlq = vlq / 0x20 " >>>= s:VLQ_BASE_SHIFT
    if vlq > 0
      " There are still more digits in this value, so we must make sure the
      " continuation bit is marked.
      let digit = or(digit, s:VLQ_CONTINUATION_BIT)
    endif
    let encoded += s:base64_encode(digit)
    if !(vlq > 0)
      break
    endif
  endwhile

  return encoded
endfunction

" Decodes the next base 64 VLQ value from the given string and returns the
" value and the rest of the string.
"
function! s:base64vlq.decode(aStr)
  let i = 0
  let strLen = strlen(a:aStr)
  let result = 0
  let shift = 0
  " let continuation, digit

  while 1
    if i >= strLen
      throw "sourcemap: Expected more digits in base 64 VLQ value."
    endif
    let digit = s:base64_decode(a:aStr[i])
    let i += 1
    let continuation = !!s:bitwise.and(digit, s:VLQ_CONTINUATION_BIT)
    let digit = s:bitwise.and(digit, s:VLQ_BASE_MASK)
    let result = result + s:bitwise.lshift(digit, shift)
    let shift += s:VLQ_BASE_SHIFT
    if !(continuation)
      break
    endif
  endwhile

  return {
        \ 'value': s:fromVLQSigned(result),
        \ 'rest': a:aStr[i :]
        \ }
endfunction

" Encode an integer in the range of 0 to 63 to a single base 64 digit.
function! s:base64_encode(aNumber)
  return s:intToCharMap[a:aNumber]
endfunction

" Decode a single base 64 digit to an integer.
"
function! s:base64_decode(aChar)
  return s:charToIntMap[a:aChar]
endfunction

let s:charToIntMap = {}
let s:intToCharMap = {}

call map(
      \ split('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', '\zs'),
      \ '[extend(s:charToIntMap, {v:val : v:key}), extend(s:intToCharMap, {v:key : v:val})]')

let &cpo = s:save_cpo
unlet s:save_cpo
" vim:sts=2 sw=2
