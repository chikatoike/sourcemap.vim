let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#of('sourcemap').load('Data.List')

" let g:sourcemap_highlight = 0
" 
" function! sourcemap#toggle_highlight()
"   call sourcemap#highlight_enable(!g:sourcemap_highlight)
" endfunction
" 
" function! sourcemap#enable_highlight(enable)
"   let g:sourcemap_highlight = a:enable
" endfunction

let s:source_maps = {}
let s:generated_maps = {}
let s:orignal_maps = {}

function! sourcemap#add_map(mapfile, force)
  let mapfile = fnamemodify(a:mapfile, ':p')
  if !has_key(s:source_maps, mapfile) || a:force
    " TODO error handling
    let consumer = sourcemap#consumer#new_file(mapfile)
    let consumer._ftime = getftime(a:mapfile)
    let s:source_maps[mapfile] = consumer
    let s:generated_maps[fnamemodify(consumer._file, ':p')] = mapfile
    for source in consumer._sources
      let s:orignal_maps[fnamemodify(source, ':p')] = mapfile
    endfor
  endif
endfunction

function! sourcemap#switch()
  let src = expand('%:p')
  let url = s:find_source_mapping_url(src)
  if url !=# ''
    call sourcemap#add_map(url, 0)
  endif

  let position = s:get_toggle_line(src, line('.'))
  if position.line > 0
    edit `=position.source`
    execute position.line
  else
    echo 'sourcemap: Cannot toggle.'
  endif
endfunction

function! s:find_source_mapping_url(src)
  let lines = readfile(a:src, -3)
  for line in lines
    let url = matchstr(line, 'sourceMappingURL=\zs.*')
    if url !=# ''
      return url
    endif
  endfor
  return ''
endfunction

function! s:get_toggle_line(src, line)
  if has_key(s:generated_maps, a:src)
    " generated -> original
    let mapfile = s:generated_maps[a:src]
    call s:update_consumer(s:source_maps[mapfile], mapfile)
    return s:source_maps[mapfile].original_line_for(a:line)
  elseif has_key(s:orignal_maps, a:src)
    " original -> generated
    let mapfile = s:orignal_maps[a:src]
    call s:update_consumer(s:source_maps[mapfile], mapfile)
    return s:source_maps[mapfile].generated_line_for(a:src, a:line)
  else
    return {
          \ 'source': '',
          \ 'line': -1,
          \ 'column': -1,
          \ 'name': ''
          \ }
  endif
endfunction

function! sourcemap#get_consumer(src)
  if has_key(s:generated_maps, a:src)
    " generated -> original
    let mapfile = s:generated_maps[a:src]
  elseif has_key(s:orignal_maps, a:src)
    " original -> generated
    let mapfile = s:orignal_maps[a:src]
  elseif has_key(s:source_maps, a:src)
    " original -> generated
    let mapfile = a:src
  else
    return 0
  endif

  call s:update_consumer(s:source_maps[mapfile], mapfile)
  return s:source_maps[mapfile]
endfunction

function! s:update_consumer(consumer, mapfile)
  if a:consumer._ftime != getftime(a:mapfile)
    call sourcemap#add_map(a:mapfile, 1)
  endif
endfunction

function! sourcemap#convert_quickfix_to_original(is_locationlist)
  if a:is_locationlist
    call setloclist(0, sourcemap#convert_loclist_to_original(getloclist(0)))
  else
    call setqflist(sourcemap#convert_loclist_to_original(getqflist()))
  endif
endfunction

function! sourcemap#add_original_to_quickfix(is_locationlist)
  if a:is_locationlist
    call setloclist(0, sourcemap#add_original_to_loclist(getloclist(0)))
  else
    call setqflist(sourcemap#add_original_to_loclist(getqflist()))
  endif
endfunction

function! sourcemap#convert_loclist_to_original(loclist)
  let loclist = deepcopy(a:loclist)
  call s:qf_normalize(loclist)
  call s:update_with_file_list(loclist)
  return map(loclist, 's:qf_get_oritinal(v:val)')
endfunction

function! sourcemap#add_original_to_loclist(loclist)
  let loclist = deepcopy(a:loclist)
  call s:qf_normalize(loclist)
  call s:update_with_file_list(loclist)

  let max = len(loclist)
  let ret = []

  for i in range(max)
    let item = loclist[i]
    call add(ret, item)

    let orig = s:qf_get_oritinal(item)
    if orig isnot item
      if i + 1 < max
        let next = loclist[i + 1]
        if orig.filename ==# next.filename && orig.lnum ==# next.lnum && orig.text ==# next.text
          continue
        endif
      endif
      call add(ret, orig)
    endif
  endfor

  return ret
endfunction

function! s:qf_normalize(loclist)
  for item in a:loclist
    if !has_key(item, 'filename')
      let item.filename = fnamemodify(bufname(item.bufnr), ':p')
    endif
  endfor
endfunction

function! s:update_with_file_list(loclist)
  let files = map(copy(a:loclist), 'v:val.filename')
  let files = s:V.Data.List.uniq(files)
  call filter(map(files, 's:find_source_mapping_url(v:val)'), 'v:val !=# ""')
  call map(copy(files), 'sourcemap#add_map(v:val, 0)')
endfunction

function! s:qf_get_oritinal(item)
  let file = a:item.filename

  if has_key(s:generated_maps, file)
    " generated -> original
    let mapfile = s:generated_maps[file]
    let position = s:source_maps[mapfile].original_line_for(a:item.lnum)
    if position.line > 0
      let item = deepcopy(a:item)
      unlet! item.bufnr
      let item.filename = position.source
      let item.lnum = position.line
      return item
    endif
  endif

  return a:item
endfunction

function! sourcemap#scope()
  return s:
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" vim:sts=2 sw=2
