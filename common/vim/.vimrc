
" --- Core behavior & filetypes ---
set nocompatible
filetype plugin indent on
syntax on

" --- Encoding, language, and help ---
set encoding=utf-8
set background=dark
set langmenu=zh_CN.UTF-8
set helplang=cn

" --- UI basics ---
set number                      " absolute line numbers
set relativenumber              " enable if you prefer relative numbers
set cursorline
set showmatch
set ruler
set nowrap
set laststatus=2
set showtabline=0
if exists('+signcolumn')
  set signcolumn=yes            " keep sign column stable to avoid text shift
endif

" --- Indentation / tabs (adjust to taste) ---
set tabstop=4
set shiftwidth=4
set noexpandtab                 " use tabs; switch to 'expandtab' if you prefer spaces
set autoindent
set smartindent

" --- Search: smart and visible ---
set ignorecase                  " case-insensitive by default
set smartcase                   " but case-sensitive if pattern has capitals
set incsearch                   " incremental search
set hlsearch                    " highlight matches
set matchtime=5                 " duration to show matching bracket (tenths of a second)

" --- Windows & splits ---
set splitright                  " :vsplit opens to the right
set splitbelow                  " :split opens below
set equalalways                 " keep splits balanced on resize

" --- Command-line completion ---
set wildmenu
set wildmode=list:longest,full  " show list, then complete to longest, then cycle

" --- Clipboard (when Vim has +clipboard) ---
if has('clipboard')
  set clipboard=unnamedplus     " use system clipboard by default
endif

" --- Whitespace visibility (toggle with :set list!) ---
set list
set listchars=tab:»·,trail:·,extends:…,precedes:…

" --- Files on disk: be resilient ---
set hidden                      " switch buffers without saving
set autoread                    " reload files changed on disk
augroup autoread_on_focus
  autocmd!
  autocmd FocusGained,BufEnter * checktime
augroup END

" --- Persistent undo & safe temp files ---
if has('persistent_undo')
  set undofile
  set undodir=~/.vim/undo,/tmp/undo     " undo files location
endif
set directory=~/.vim/tmp//,~/tmp//,/tmp//      " swap files location
set backupdir=~/.vim/tmp//,~/tmp//,/tmp//      " backups (enable with :set backup if desired)
" (keep swapfiles ON so the above directory is actually used)

" --- Timings & UI polish ---
set ttimeout
set timeoutlen=500              " mapping timeout (ms)
set ttimeoutlen=10              " keycode timeout (ms)
set updatetime=300              " quicker CursorHold, diagnostics refresh
set scrolloff=5                 " keep context when scrolling
set sidescrolloff=5
set shortmess+=filmnrxoOtTI     " quieter messages while keeping essentials

" --- Completion behavior (built-in) ---
" menuone: show popup even for a single match; noinsert: don't insert until chosen
" noselect: don't select first item automatically; preview: show doc preview when available
set completeopt=menu,preview
if has('patch-7.4.775')
  set completeopt+=menuone
  set completeopt+=noinsert
  set completeopt+=noselect
else
  set completeopt+=menuone
endif

" --- Folding (built-in) ---
set foldmethod=marker           " alternatives: indent | syntax | expr
set foldlevel=99                " open all by default; zM to close, zR to open all

" --- Colors & terminal capabilities ---
if has('termguicolors')
  set termguicolors
endif

" --- Mouse (optional, helpful in terminals/SSH) ---
set mouse=a

" --- Modelines: allow per-file hints safely ---
set modeline
set modelines=5

" --- Movement & selection behavior ---
set whichwrap+=<,>,h,l          " allow wrapping with arrow keys/h/l
set selection=exclusive
set selectmode=mouse,key

" --- Useful mappings ---
let mapleader=";"

" Quick window navigation with Ctrl + h/j/k/l
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Toggle search highlight quickly
nnoremap <Leader>/ :set hlsearch!<CR>

" Quick save/quit
nnoremap <Leader>w :write<CR>
nnoremap <Leader>q :quit<CR>
nnoremap <Leader>x :xit<CR>

" Open a file browser in current file's directory (built-in netrw)
nnoremap <Leader>e :Ex<CR>

" --- Paste mode toggle (useful when pasting code) ---
set pastetoggle=<F2>

" --- Mode-indicative cursor shapes (terminal & GUI) ---
" Terminal Vim (DECSCUSR): 2=block, 4=underline, 6=bar
if !has('gui_running')
  if exists('&t_SI') | let &t_SI = "\e[6 q" | endif
  if exists('&t_SR') | let &t_SR = "\e[4 q" | endif
  if exists('&t_EI') | let &t_EI = "\e[2 q" | endif
endif

" GUI Vim: fine control via 'guicursor' and GUI-only options
if has('gui_running')
  highlight Cursor  guifg=white guibg=black
  highlight iCursor guifg=white guibg=SteelBlue
  set guicursor=n-v-c:block-Cursor
  set guicursor+=i:ver100-iCursor
  set guicursor+=n-v-c:blinkon0
  set guicursor+=i:blinkwait10
  " mirror original guioptions removals (GUI only)
  set guioptions-=r
  set guioptions-=L
  set guioptions-=b
endif

" --- Statusline ---
set statusline=\ %<%F[%1*%M%*%n%R%H]%=\ %y\ %0(%{&fileformat}\ %{&encoding}\ %c:%l/%L%)
