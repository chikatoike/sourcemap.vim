" Copyright 2012 chikatoike
" Copyright 2011 Mozilla Foundation and contributors
" Licensed under the New BSD license. See LICENSE or:
" http://opensource.org/licenses/BSD-3-Clause
let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#of('sourcemap').load('Web.Json', 'System.Filepath')

let s:base64VLQ = sourcemap#base64vlq#new()

let s:SourceMapConsumer = {}

" The version of the source mapping spec that we are consuming.
let s:SourceMapConsumer._version = 3

function! sourcemap#consumer#new_file(path)
  let json = join(readfile(a:path), '')
  return sourcemap#consumer#new_json(json)
endfunction

function! sourcemap#consumer#new_json(json)
  let source_map = s:V.Web.Json.decode(a:json)
  return sourcemap#consumer#new(source_map)
endfunction

" A SourceMapConsumer instance represents a parsed source map which we can
" query for information about the original file positions by giving it a file
" position in the generated source.
"
" The only parameter is the raw source map (either as a JSON string, or
" already parsed to an object). According to the spec, source maps have the
" following attributes:
"
"   - version: Which version of the source map spec this map is following.
"   - sources: An array of URLs to the original source files.
"   - names: An array of identifiers which can be referrenced by individual mappings.
"   - sourceRoot: Optional. The URL root from which all sources are relative.
"   - mappings: A string of base64 VLQs which contain the actual mappings.
"   - file: The generated file this source map is associated with.
"
" Here is an example source map, taken from the source map spec[0]:
"
"     {
"       version : 3,
"       file: "out.js",
"       sourceRoot : "",
"       sources: ["foo.js", "bar.js"],
"       names: ["src", "maps", "are", "fun"],
"       mappings: "AA,AB;;ABCDE;"
"     }
"
" [0]: https://docs.google.com/document/d/1U1RGAehQwRypUTovF1KRlpiOFze0b-_2gc6fAH0KY0k/edit?pli=1#
"
function! sourcemap#consumer#new(source_map)
  let sourceMap = a:source_map

  let l:version = sourceMap.version
  let sources = sourceMap.sources
  let names = sourceMap.names
  let sourceRoot = get(sourceMap, 'sourceRoot', '')
  let mappings = sourceMap.mappings
  let file = sourceMap.file

  let consumer = deepcopy(s:SourceMapConsumer)

  if l:version != consumer._version
    throw s:Error('Unsupported version: ' + l:version)
  endif

  let consumer._names = names
  let consumer._sources = sources " TODO use ArraySet?
  let consumer._file = file

  " `self._generatedMappings` hold the parsed mapping coordinates from the
  " source map's "mappings" attribute. Each object in the array is of the
  " form
  "
  "     {
  "       generatedLine: The line number in the generated code,
  "       generatedColumn: The column number in the generated code,
  "       source: The path to the original source file that generated this
  "               chunk of code,
  "       originalLine: The line number in the original source that
  "                     corresponds to this chunk of generated code,
  "       originalColumn: The column number in the original source that
  "                       corresponds to this chunk of generated code,
  "       name: The name of the original symbol which generated this chunk of
  "             code.
  "     }
  "
  " All properties except for `generatedLine` and `generatedColumn` can be
  " `null`.
  let consumer._generatedMappings = []
  let consumer._parseMappings(mappings, sourceRoot)
  return consumer
endfunction

" Parse the mappings in a string in to a data structure which we can easily
" query (an ordered list in self._generatedMappings).
"
function! s:SourceMapConsumer._parseMappings(aStr, aSourceRoot)
  let generatedLine = 1
  let previousGeneratedColumn = 0
  let previousOriginalLine = 0
  let previousOriginalColumn = 0
  let previousSource = 0
  let previousName = 0
  let mappingSeparator = ',;'
  let str = a:aStr
  " let mapping
  " let temp

  while strlen(str) > 0
    if str[0] ==# ';'
      let generatedLine += 1
      let str = str[1 :]
      let previousGeneratedColumn = 0
    elseif str[0] ==# ','
      let str = str[1 :]
    else
      let mapping = {}
      let mapping.generatedLine = generatedLine

      " Generated column.
      let temp = s:base64VLQ.decode(str)
      let mapping.generatedColumn = previousGeneratedColumn + temp.value
      let previousGeneratedColumn = mapping.generatedColumn
      let str = temp.rest

      " s/\V\<mappingSeparator.test(str.charAt(0))/(stridx(mappingSeparator, str[0]) >= 0)/gI

      if strlen(str) > 0 && !(stridx(mappingSeparator, str[0]) >= 0)
        " Original source.
        let temp = s:base64VLQ.decode(str)
        if !empty(a:aSourceRoot)
          let mapping.source = s:V.System.Filepath.join(a:aSourceRoot, self._sources[previousSource + temp.value])
        else
          let mapping.source = self._sources[previousSource + temp.value]
        endif
        let previousSource += temp.value
        let str = temp.rest
        if strlen(str) == 0 || (stridx(mappingSeparator, str[0]) >= 0)
          throw s:Error('Found a source, but no line and column')
        endif

        " Original line.
        let temp = s:base64VLQ.decode(str)
        let mapping.originalLine = previousOriginalLine + temp.value
        let previousOriginalLine = mapping.originalLine
        " Lines are stored 0-based
        let mapping.originalLine += 1
        let str = temp.rest
        if strlen(str) == 0 || (stridx(mappingSeparator, str[0]) >= 0)
          throw s:Error('Found a source and line, but no column')
        endif

        " Original column.
        let temp = s:base64VLQ.decode(str)
        let mapping.originalColumn = previousOriginalColumn + temp.value
        let previousOriginalColumn = mapping.originalColumn
        let str = temp.rest

        if strlen(str) > 0 && !(stridx(mappingSeparator, str[0]) >= 0)
          " Original name.
          let temp = s:base64VLQ.decode(str)
          let mapping.name = self._names[previousName + temp.value]
          let previousName += temp.value
          let str = temp.rest
        endif
      endif

      call add(self._generatedMappings, mapping)
    endif
  endwhile
endfunction

let s:error_position = {
      \ 'source': '',
      \ 'line': -1,
      \ 'column': -1,
      \ 'name': ''
      \ }

" Returns the original source, line, and column information for the generated
" source's line and column positions provided. The only argument is an object
" with the following properties:
"
"   - line: The line number in the generated source.
"   - column: The column number in the generated source.
"
" and an object is returned with the following properties:
"
"   - source: The original source file, or null.
"   - line: The line number in the original source, or null.
"   - column: The column number in the original source, or null.
"   - name: The original identifier, or null.
"
function! s:SourceMapConsumer.original_position_for(position)
  let needle = {
        \ 'generatedLine': a:position.line,
        \ 'generatedColumn': a:position.column
        \ }

  if needle.generatedLine <= 0
    throw s:Error('Line must be greater than or equal to 1.')
  endif
  if needle.generatedColumn < 0
    throw s:Error('Column must be greater than or equal to 0.')
  endif

  let index = s:binary_search(needle, self._generatedMappings, function('s:compare_generated_position'))

  if index >= 0
    let mapping = self._generatedMappings[index]
    return {
          \ 'source': get(mapping, 'source', ''),
          \ 'line': get(mapping, 'originalLine', -1),
          \ 'column': get(mapping, 'originalColumn', -1),
          \ 'name': get(mapping, 'name', '')
          \ }
  else
    return s:error_position
  endif
endfunction

function! s:SourceMapConsumer.original_line_for(line)
  let needle = {
        \ 'generatedLine': a:line,
        \ }

  if a:line <= 0
    throw s:Error('Line must be greater than or equal to 1.')
  endif

  " TODO haystack is not sorted with attribute "originalLine".
  let index = s:linear_search(needle, self._generatedMappings, function('s:compare_generated_line'))

  if index >= 0
    let mapping = self._generatedMappings[index]
    return {
          \ 'source': get(mapping, 'source', ''),
          \ 'line': get(mapping, 'originalLine', -1),
          \ 'column': get(mapping, 'originalColumn', -1),
          \ 'name': get(mapping, 'name', '')
          \ }
  else
    return s:error_position
  endif
endfunction

function! s:SourceMapConsumer.generated_line_for(source, line)
  let needle = {
        \ 'source': a:source,
        \ 'originalLine': a:line,
        \ }

  if a:line <= 0
    throw s:Error('Line must be greater than or equal to 1.')
  endif

  let index = s:binary_search(needle, self._generatedMappings, function('s:compare_original_line'))

  if index >= 0
    let mapping = self._generatedMappings[index]
    return {
          \ 'source': self._file,
          \ 'line': get(mapping, 'generatedLine', -1),
          \ 'column': get(mapping, 'generatedColumn', -1),
          \ 'name': get(mapping, 'name', '')
          \ }
  else
    return s:error_position
  endif
endfunction

function! s:linear_search(needle, haystack, compare)
  let max = len(a:haystack)
  let i = 0

  while i < max
    if a:compare(a:haystack[i], a:needle) == 0
      return i
    endif
    let i += 1
  endwhile

  return -1
endfunction

" This is an implementation of binary search which will always try and return
" the next lowest value checked if there is no exact hit. This is because
" mappings between original and generated line/col pairs are single points,
" and there is an implicit region between each of them, so a miss just means
" that you aren't on the very start of a region.
"
" @param aNeedle The element you are looking for.
" @param aHaystack The array that is being searched.
" @param aCompare A function which takes the needle and an element in the
"     array and returns -1, 0, or 1 depending on whether the needle is less
"     than, equal to, or greater than the element, respectively.
"
function! s:binary_search(needle, haystack, compare)
  let low = -1
  let high = len(a:haystack)

  while 1
    let mid = ((high - low) / 2) + low
    let cmp = a:compare(a:needle, a:haystack[mid])
    if cmp == 0
      " Found the element we are looking for.
      return mid
    elseif cmp > 0
      " aHaystack[mid] is greater than our needle.
      if high - mid > 1
        " The element is in the upper half.
        let low = mid
      else
        " We did not find an exact match, return the next closest one
        " (termination case 2).
        return mid
      endif
    else
      " aHaystack[mid] is less than our needle.
      if mid - low > 1
        " The element is in the lower half.
        let high = mid
      else
        " The exact needle element was not found in this haystack. Determine if
        " we are in termination case (2) or (3) and return the appropriate thing.
        return low < 0 ? -1 : low
      endif
    endif
  endwhile
endfunction

" To perform a binary search on the mappings, we must be able to compare
" two mappings.
"
function! s:compare_generated_position(mappingA, mappingB)
  let cmp = a:mappingA.generatedLine - a:mappingB.generatedLine
  return cmp == 0
        \ ? a:mappingA.generatedColumn - a:mappingB.generatedColumn
        \ : cmp
endfunction

function! s:compare_generated_line(mappingA, mappingB)
  return a:mappingA.generatedLine - a:mappingB.generatedLine
endfunction

function! s:compare_original_position(mappingA, mappingB)
  return !(a:mappingA.source ==? a:mappingB.source
        \ && a:mappingA.originalLine == a:mappingB.originalLine
        \ && a:mappingA.originalColumn == a:mappingB.originalColumn)
endfunction

function! s:compare_original_line(mappingA, mappingB)
  return !(a:mappingA.source ==? a:mappingB.source
        \ && a:mappingA.originalLine == a:mappingB.originalLine)
endfunction

function! s:Error(message)
  return 'sourcemap: ' . a:message
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" vim:sts=2 sw=2
