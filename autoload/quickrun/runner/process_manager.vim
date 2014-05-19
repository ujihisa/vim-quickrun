" quickrun: runner/process_manager: Runs by Vital.ProcessManager
" Author:  ujihisa <ujihisa at gmail com>
" License: zlib License
" Known issues:
"   * if a run stalled, next run will wait. It should cancel previous one
"   automatically.
"   * kill interface doesn't exist yet (related to the previous issue)

let s:save_cpo = &cpo
set cpo&vim

let s:runner = {
\   'config': {
\     'load': 'load %s',
\     'prompt': '>>> ',
\   }
\ }

let s:P = g:quickrun#V.import('ProcessManager')

augroup plugin-quickrun-process-manager
augroup END

function! s:runner.validate()
  if !s:P.is_available()
    throw 'Needs vimproc.'
  endif
endfunction

function! s:runner.run(commands, input, session)
  let type = a:session.config.type
  let message = a:session.build_command(self.config.load)
  let [out, err, t] = s:execute(
        \ type,
        \ a:session,
        \ self.config.prompt,
        \ message)
  call a:session.output(out . (err ==# '' ? '' : printf('!!!%s!!!', err)))
  if t ==# 'matched'
    return 0
  elseif t ==# 'inactive'
    call s:P.kill(type)
    call a:session.output('!!!process is inactive. try again.!!!')
    return 0
  elseif t ==# 'timedout' || t ==# 'preparing'
    let key = a:session.continue()
    augroup plugin-quickrun-process-manager
      execute 'autocmd! CursorHold,CursorHoldI * call'
      \       's:receive(' . string(key) . ')'
    augroup END
    let self.phase = t
    if t == 'preparing'
      let self._message = message
    endif
    let self._autocmd = 1
    let self._updatetime = &updatetime
    let &updatetime = 50
  else
    call a:session.output(printf('Must not happen. t: %s', t))
    return 0
  endif
endfunction

function! s:execute(type, session, prompt, message)
  let cmd = printf("%s %s", a:session.config.command, a:session.config.cmdopt)
  let cmd = g:quickrun#V.iconv(cmd, &encoding, &termencoding)
  let t = s:P.touch(a:type, cmd)
  if t ==# 'new'
    let [out, err, t2] = s:P.read(a:type, [a:prompt])
    if t2 == 'matched' " wow it's so quick
      return [out, err, t2]
    else " it's normal
      return [out, err, 'preparing']
    endif
  elseif t ==# 'inactive'
    return ['', '', 'inactive']
  endif

  if a:message !=# ''
    call s:P.writeln(a:type, a:message)
  endif
  return s:P.read(a:type, [a:prompt])
endfunction

function! s:receive(key)
  if s:_is_cmdwin()
    return 0
  endif

  let session = quickrun#session(a:key)
  if session.runner.phase == 'ready'
    let [out, err, t] = s:P.read(session.config.type, [session.runner.config.prompt])
    call session.output(out . (err ==# '' ? '' : printf('!!!%s!!!', err)))
    if t ==# 'matched'
      call session.finish(1)
      return 1
    else " 'timedout'
      call feedkeys(mode() ==# 'i' ? "\<C-g>\<ESC>" : "g\<ESC>", 'n')
      return 0
    endif
  elseif session.runner.phase == 'preparing'
    let [out, err, t] = s:P.read(session.config.type, [session.runner.config.prompt])
    if t ==# 'matched'
      let session.runner.phase = 'ready'
      call s:P.writeln(session.config.type, session.runner._message)
    else
      " silently ignore preparation outputs
    endif
    call feedkeys(mode() ==# 'i' ? "\<C-g>\<ESC>" : "g\<ESC>", 'n')
    return 0
  else
    call session.output(printf(
          \ 'Must not happen -- it should be unreachable. phase: %s',
          \ session.runner.phase))
    return 0
  endif
endfunction

function! s:runner.sweep()
  if has_key(self, '_autocmd')
    autocmd! plugin-quickrun-process-manager
  endif
  if has_key(self, '_updatetime')
    let &updatetime = self._updatetime
  endif
endfunction

function! quickrun#runner#process_manager#new()
  return deepcopy(s:runner)
endfunction

" TODO use vital's
function! s:_is_cmdwin()
  return bufname('%') ==# '[Command Line]'
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
