let s:save_cpo = &cpo
set cpo&vim

" command! SourceMapToggleHighlight  call sourcemap#toggle_highlight()
" command! SourceMapEnableHighlight  call sourcemap#enable_highlight(1)
" command! SourceMapDisableHighlight call sourcemap#enable_highlight(0)

command! -nargs=* -complete=file SourceMapAddMap call sourcemap#add_map(<q-args>, 1)
command! SourceMapSwitch call sourcemap#switch()


let &cpo = s:save_cpo
unlet s:save_cpo
" vim:sts=2 sw=2
