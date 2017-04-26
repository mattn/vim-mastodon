let s:URL_PROTOCOL = '\%([Hh][Tt][Tt][Pp]\|[Hh][Tt][Tt][Pp][Ss]\|[Ff][Tt][Pp]\)://'
let s:URL_PROTOCOL_HTTPS = '\%([Hh][Tt][Tt][Pp][Ss]\)://'
let s:URL_PROTOCOL_NON_HTTPS = '\%([Hh][Tt][Tt][Pp]\|[Ff][Tt][Pp]\)://'
let s:URL_DOMAIN_CHARS = '[a-zA-Z0-9!$&''()*+,.:;=?@_~%#-]'
let s:URL_DOMAIN_END_CHARS = '[a-zA-Z0-9!$&''*+=?@_~%#-]'
let s:URL_DOMAIN_PARENS = '('.s:URL_DOMAIN_CHARS.'*)'
let s:URL_DOMAIN = '\%('.'\%('.s:URL_DOMAIN_CHARS.'*'.s:URL_DOMAIN_PARENS.'\)'.'\|'.'\%('.s:URL_DOMAIN_CHARS.'*'.s:URL_DOMAIN_END_CHARS.'\)'.'\)'
let s:URL_PATH_CHARS = '[a-zA-Z0-9!$&''()*+,./:;=?@_~%#-]'
let s:URL_PARENS = '('.s:URL_PATH_CHARS.'*)'
let s:URL_PATH_END_CHARS = '[a-zA-Z0-9!$&''*+/=?@_~%#-]'
let s:URL_PATH = '\%('.'\%('.s:URL_PATH_CHARS.'*'.s:URL_PARENS.'\)'.'\|'.'\%('.s:URL_PATH_CHARS.'*'.s:URL_PATH_END_CHARS.'\)'.'\)'
let s:URLMATCH = s:URL_PROTOCOL.s:URL_DOMAIN.'\%(/'.s:URL_PATH.'\=\)\='
let s:URLMATCH_HTTPS = s:URL_PROTOCOL_HTTPS.s:URL_DOMAIN.'\%(/'.s:URL_PATH.'\=\)\='
let s:URLMATCH_NON_HTTPS = s:URL_PROTOCOL_NON_HTTPS.s:URL_DOMAIN.'\%(/'.s:URL_PATH.'\=\)\='

let s:host = get(g:, 'mastodon_host')
let s:access_token = get(g:, 'mastodon_access_token')

function! s:to_text(str)
  let str = a:str
  let str = substitute(str, '<br\s*/\?>', "\n", 'g')
  let str = substitute(str, '<\([^/]\+\)/>', '', 'g')
  while 1
    let tmp = substitute(str, '<\([^ >]\+\)\%([^>]*\)>\(\_[^<]*\)</\1>', '\2', 'g')
    if tmp == str
      break
    endif
    let str = tmp
  endwhile
  let str = substitute(str, '&gt;', '>', 'g')
  let str = substitute(str, '&lt;', '<', 'g')
  let str = substitute(str, '&quot;', '"', 'g')
  let str = substitute(str, '&apos;', "'", 'g')
  let str = substitute(str, '&nbsp;', ' ', 'g')
  let str = substitute(str, '&yen;', '\&#65509;', 'g')
  let str = substitute(str, '&#\(\d\+\);', '\=s:nr2enc_char(submatch(1))', 'g')
  let str = substitute(str, '&amp;', '\&', 'g')
  let str = substitute(str, '&raquo;', '>', 'g')
  let str = substitute(str, '&laquo;', '<', 'g')
  return str
endfunction

function! s:format(item)
  if !empty(a:item.reblog)
    return a:item.account.acct . ': BOOST: ' . s:to_text(a:item.reblog.content)
  endif
  return a:item.account.acct . ': ' . s:to_text(a:item.content)
endfunction

function! s:append_line(expr, text) abort
  if bufnr(a:expr) == -1
    return
  endif
  let mode = mode()
  let oldnr = winnr()
  let winnr = bufwinnr(a:expr)
  if oldnr != winnr
    if winnr == -1
      silent exec "sp ".escape(bufname(bufnr(a:expr)), ' \')
    else
      exec winnr.'wincmd w'
    endif
  endif
  setlocal modifiable | call append('$', a:text) | setlocal nomodifiable
  let pos = getpos('.')
  let pos[1] = line('$')
  let pos[2] = 9999
  call setpos('.', pos)
  if oldnr != winnr
    if winnr == -1
      silent hide
    endif
  endif

  exec oldnr.'wincmd w'
  if mode =~# '[sSvV]'
    silent! normal gv
  endif
  if mode !~# '[cC]'
    redraw
  endif
endfunction

function! s:show_timeline(items)
  let winnum = bufwinnr(bufnr('mastodon://'))
  if winnum != -1
    if winnum != bufwinnr('%')
      exe winnum 'wincmd w'
    endif
    setlocal modifiable
  else
    silent noautocmd rightbelow new
    setlocal noswapfile
    silent exec 'noautocmd file' 'mastodon://'
  endif

  let old_undolevels = &undolevels
  set undolevels=-1
  filetype detect
  silent %d _
  call setline(1, map(a:items, 's:format(v:val)'))
  let &undolevels = old_undolevels
  setlocal buftype=acwrite bufhidden=hide noswapfile
  setlocal bufhidden=wipe
  setlocal nomodified
  setlocal nomodifiable

  syntax clear
  syntax match mastodonUser /^.\{-1,}:/
  syntax match mastodonTime /|[^|]\+|$/ contains=mastodonTimeBar
  syntax match mastodonTimeBar /|/ contained
  execute 'syntax match mastodonLink "\<'.s:URLMATCH.'"'
  syntax match mastodonReply "\w\@<!@\w\+"
  syntax match mastodonLink "\w\@<!#[^[:blank:][:punct:]\u3000\u3001]\+"
  syntax match mastodonLink "\w\@<!$\a\+"
  syntax match mastodonTitleStar /\*$/ contained
  syntax match mastodonReply "\w\@<!@\w\+"
  syntax match mastodonBoost "\(^[^:]\+: \)\@<=BOOST:.*"
  highlight default link mastodonUser Identifier
  highlight default link mastodonTime String
  highlight default link mastodonTimeBar Ignore
  highlight default link mastodonTitle Title
  highlight default link mastodonTitleStar Ignore
  highlight default link mastodonLink Underlined
  highlight default link mastodonReply Label
  highlight default link mastodonBoost Directory
endfunction

function! mastodon#complete(alead, cline, cpos)
  if len(split(a:cline, '\s')) > 2
    return []
  endif
  return filter(['toot', 'timeline', 'stream'], 'stridx(v:val, a:alead)>=0')
endfunction

function! mastodon#call(...)
  let method = get(a:000, 0, '')
  let args = get(a:000, 1, '')
  if method == 'timeline'
    let res = webapi#http#get('https://mstdn.jp/api/v1/timelines/home',
	\{
	\},
	\{
    \ 'Authorization': 'Bearer ' . s:access_token,
    \})
    if res.status != 200
      return res.message
    endif
    let items = webapi#json#decode(res.content)
    call s:show_timeline(items)
  elseif method == 'toot'
    let text = a:000[1:]
    let res = webapi#http#post('https://mstdn.jp/api/v1/statuses',
	\{
	\  'status': text,
	\},
	\{
    \ 'Authorization': 'Bearer ' . s:access_token,
    \})
    if res.status != 200
      return res.message
    endif
  elseif method == 'stream'
    call s:show_timeline([])
    call webapi#http#stream(
	\{
	\  'url':    'https://mstdn.jp/api/v1/streaming/public/local',
	\  'header': {'Authorization': 'Bearer ' . s:access_token},
	\  'out_cb': function('mastodon#add_item'),
	\})
  endif
endfunction

let s:lastline = ''
function! mastodon#add_item(data)
  let data = a:data
  if data =~ '^event:'
    let s:lastline = substitute(data, '^event:\s*\(\w\+\)', '\1', '')
  elseif data =~ '^data:' && s:lastline == 'update'
    let data = substitute(data, '^data:\s*', '', '')
    let item = webapi#json#decode(data)
    call s:append_line('mastodon://', s:format(item))
  endif
endfunction
