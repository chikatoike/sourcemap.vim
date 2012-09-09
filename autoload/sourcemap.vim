let s:save_cpo = &cpo
set cpo&vim

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

function! s:update_consumer(consumer, mapfile)
  if a:consumer._ftime != getftime(a:mapfile)
    call sourcemap#add_map(a:mapfile, 1)
  endif
endfunction

function! sourcemap#scope()
  return s:
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" vim:sts=2 sw=2
