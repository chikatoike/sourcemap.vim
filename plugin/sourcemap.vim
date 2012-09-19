if exists('g:loaded_sourcemap')
  finish
endif
let g:loaded_sourcemap = 1

let s:save_cpo = &cpo
set cpo&vim

" command! SourceMapToggleHighlight  call sourcemap#toggle_highlight()
" command! SourceMapEnableHighlight  call sourcemap#enable_highlight(1)
" command! SourceMapDisableHighlight call sourcemap#enable_highlight(0)

command! -nargs=* -complete=file SourceMapAddMap call sourcemap#add_map(<q-args>, 1)
command! SourceMapSwitch call sourcemap#switch()
command! SourceMapConvertQuickfixToOriginal call sourcemap#convert_quickfix_to_original(0)
command! SourceMapConvertLocListToOriginal  call sourcemap#convert_quickfix_to_original(1)
command! SourceMapAddOriginalToQuickfix call sourcemap#add_original_to_quickfix(0)
command! SourceMapAddOriginalToLocList  call sourcemap#add_original_to_quickfix(1)


let &cpo = s:save_cpo
unlet s:save_cpo
" vim:sts=2 sw=2
