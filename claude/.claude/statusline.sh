#!/usr/bin/env bash
[ -n "$BASH_VERSION" ] || exec bash "$0" "$@"   # re-exec under bash if run by another shell
# Status line (2 lines); segments with absent JSON fields are omitted:
#   PWD | git branch[*!] | wt:worktree[<-orig] | session name
#   model | ctx N% | 5h N% 7d N% | cache N% [warm/cold] [N miss]
# Requires: bash 3.2+, jq 1.5+, git 2.17+
#
# jq parses, sanitizes and renders everything that comes from the JSON; bash only runs git and
# prints. Untrusted input reaches eval only as @sh-quoted values of four fixed variable names.
#
# Palette follows oh-my-zsh "dstj" theme (ANSI 16-color):
#   dir = fg_bold[blue], git = fg[green] + fg[red]"*!" (matches git_prompt_info)
#   wt = fg[magenta] (%n user), session = default fg, model = fg[cyan] (RPROMPT clock)
#   usage: ok green / warn yellow / crit red (FAIL:)
#   line 2 is dim (secondary info), except labels and critical values (normal intensity)
readonly C_DIR=$'\e[1;34m' C_BRANCH=$'\e[32m' C_DIRTY=$'\e[31m' C_RESET=$'\e[0m'
readonly NAME_MAX=40   # max codepoints for session / worktree names (CJK takes 2 columns each)
# Seconds a git segment is reused within a session. Keep it below settings.json refreshInterval
# so idle refreshes still pick up changes made by background subagents.
readonly GIT_TTL=5

# Strip control, bidi and invisible format chars. ZWJ / ZWNJ are kept (emoji, some scripts).
readonly JQ_CLEAN='
  def is_ctrl: . < 32 or (. >= 127 and . <= 159);                       # C0, DEL, C1
  def is_bidi: (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297)   # U+202A-202E, U+2066-2069
            or . == 1564 or . == 8206 or . == 8207;                      # ALM, LRM, RLM
  def is_invis: . == 173 or . == 6158 or . == 8203 or . == 8288         # SHY, MVS, ZWSP, WJ
             or . == 8232 or . == 8233 or . == 65279                     # line/para sep, BOM
             or (. >= 917504 and . <= 917631);                           # tag chars
  def clean:   tostring | explode | map(select((is_ctrl or is_bidi or is_invis) | not)) | implode;
'

# Print " | ref[ -> upstream][*!]"; non-zero outside a git repo.
# Mirrors oh-my-zsh git_prompt_info + parse_git_dirty (lib/git.zsh):
#   ref: branch, else exact tag, else `rev-parse --short` (unique abbrev), else 7-char oid
#   git config oh-my-zsh.hide-info=1 hides the segment; oh-my-zsh.hide-dirty=1 drops "*!"
#   env vars (must be exported from .zshrc; plain zsh variables never reach this script):
#     ZSH_THEME_GIT_SHOW_UPSTREAM  set (even empty) -> " -> origin/main"
#     DISABLE_UNTRACKED_FILES_DIRTY=true            -> untracked files are not dirty
#     GIT_STATUS_IGNORE_SUBMODULES unset -> dirty; git -> repo config; none|untracked|dirty|all
# --no-ahead-behind needs git 2.17; --no-optional-locks avoids racing the user's own git.
# core.fsmonitor=false stops `git status` from running a repo-configured hook, at the cost of
# a full scan on large repos (deliberately unlike oh-my-zsh). Filter drivers are not covered;
# rely on git's safe.directory.
git_segment() {
  local git=(git -C "$1" --no-optional-locks -c core.fsmonitor=false)
  local flags=(--porcelain=v2 --branch --no-ahead-behind) st ref oid up='' dirty=''
  local k v hide_info='' hide_dirty=''

  # one call for both keys; last value wins, as with `git config --get` (keys come back lowercased)
  # here-string, not < <(...): process substitution is unavailable when bash 3.2 runs as sh
  while read -r k v; do
    case $k in
      oh-my-zsh.hide-info)  hide_info=$v ;;
      oh-my-zsh.hide-dirty) hide_dirty=$v ;;
    esac
  done <<<"$("${git[@]}" config --get-regexp '^oh-my-zsh\.hide-(info|dirty)$' 2>/dev/null)"
  [[ $hide_info == 1 ]] && return 0

  if [[ $hide_dirty == 1 ]]; then
    flags+=(--untracked-files=no --ignore-submodules=all)   # result unused; scan less
  else
    [[ ${DISABLE_UNTRACKED_FILES_DIRTY-} == true ]] && flags+=(--untracked-files=no)
    case ${GIT_STATUS_IGNORE_SUBMODULES-} in
      git) ;;                                                 # let git / .gitmodules decide
      none|untracked|dirty|all) flags+=(--ignore-submodules="$GIT_STATUS_IGNORE_SUBMODULES") ;;
      *) flags+=(--ignore-submodules=dirty) ;;                # unset or invalid: omz default
    esac
  fi
  st=$'\n'$("${git[@]}" status "${flags[@]}" 2>/dev/null) || return

  ref=${st#*$'\n# branch.head '}; ref=${ref%%$'\n'*}
  oid=${st#*$'\n# branch.oid '};  oid=${oid%%$'\n'*}
  # upstream comes free with --branch; omz uses `rev-parse @{upstream}`, which also hides a gone one
  if [[ -n ${ZSH_THEME_GIT_SHOW_UPSTREAM+x} && $st == *$'\n# branch.upstream '* ]]; then
    up=${st#*$'\n# branch.upstream '}; up=" -> ${up%%$'\n'*}"
  fi
  [[ $hide_dirty != 1 && $st == *$'\n'[^#]* ]] && dirty="${C_DIRTY}*!"   # any non-header line
  if [[ $ref == '(detached)' ]]; then
    ref=$("${git[@]}" describe --tags --exact-match HEAD 2>/dev/null) \
      || ref=$("${git[@]}" rev-parse --short HEAD 2>/dev/null) || ref=${oid:0:7}
  fi
  ref+=$up
  # git only forbids ASCII control chars in refs, so clean non-ASCII ones (bidi, C1)
  if [[ $ref == *[![:ascii:]]* ]]; then
    ref=$(jq -Rj "$JQ_CLEAN"'clean' <<<"$ref" 2>/dev/null) || ref='?'   # not oid: may be "(initial)"
  fi
  ref=${ref//[[:cntrl:]]/?}   # defense in depth; also keeps the segment one line for the cache

  printf ' | %s' "${C_BRANCH}${ref}${dirty}${C_RESET}"
}

# git_segment, reused for GIT_TTL seconds per (session, dir). Claude Code cancels the script when
# a new update arrives, so a slow `git status` can otherwise be cancelled over and over.
# Cache: ${XDG_CACHE_HOME:-~/.cache}/claude-statusline/<session_id>-<cksum of dir>, mode 700.
# File format: "<epoch>\n<segment>\n". Without a usable session id or cache dir, runs git directly.
cached_git_segment() {
  local d f crc now tmp ts='' seg='' new=''
  [[ $2 =~ ^[A-Za-z0-9_-]{1,128}$ ]] || { git_segment "$1"; return; }
  if [[ -n ${XDG_CACHE_HOME-} ]]; then d=$XDG_CACHE_HOME
  elif [[ -n ${HOME-} ]]; then d=$HOME/.cache
  else git_segment "$1"; return
  fi
  d+=/claude-statusline
  (umask 077; mkdir -p "$d") 2>/dev/null
  [[ -d $d && ! -L $d && -O $d ]] || { git_segment "$1"; return; }

  crc=$(printf %s "$1" | cksum); f=$d/$2-${crc// /-}   # "crc size" -> "crc-size"
  now=${EPOCHSECONDS:-$(date +%s)}                      # bash 5+ avoids the fork
  if [[ -f $f && ! -L $f ]]; then
    { IFS= read -r ts && IFS= read -r seg; } 2>/dev/null <"$f"
    if [[ $ts =~ ^[0-9]+$ ]] && (( ts <= now && now - ts < GIT_TTL )); then
      printf '%s' "$seg"; return 0
    fi
  else
    new=1
  fi

  seg=$(git_segment "$1")
  tmp=$f.$$   # write + rename, so a cancelled run never leaves a half-written cache
  { printf '%s\n%s\n' "$now" "$seg" >"$tmp" && mv -f "$tmp" "$f"; } 2>/dev/null || rm -f "$tmp"
  # first write for this session/dir: prune entries untouched for a day (dead sessions, tmp files)
  [[ -n $new ]] && find "$d" -type f -mmin +1440 -exec rm -f {} + 2>/dev/null
  printf '%s' "$seg"
}

# stdin JSON -> one line of shell assignments for main to eval:
#   dir (raw, only for git -C), disp (cleaned), sid (session_id, validated by the cache),
#   tail (line 1 after the git segment), line2
# -R -s + fromjson: invalid or non-object JSON becomes {} instead of aborting jq, so the PWD
# fallback is cleaned too.
parse_input() {
  jq -r -R -s --argjson max "$NAME_MAX" "$JQ_CLEAN"'
    # zsh %~ : $HOME -> ~ (named dirs from `hash -d` are zsh-only and not reproduced)
    def tilde: (env.HOME // "" | rtrimstr("/")) as $h
      | if $h != "" and (. == $h or startswith($h + "/")) then "~" + .[($h | length):] else . end;

    # Typed readers: the value if the field exists with the right type, else null.
    def get(f; t): first((try f catch null | t), null);
    def S(f): get(f; strings | clean | select(. != ""));                      # string
    def T(f): S(f) | if length > $max then .[:$max - 1] + "…" else . end;     # string, truncated
    def B(f): get(f; booleans);
    # percentage 0-100. +0.5|floor, not round: libm-dependent in jq 1.5, can yield -0.
    def P(f): get(f; numbers | . + 0.5 | (if . < 0 then 0 elif . > 100 then 100 else . end) | floor);

    # Each colored piece sets and resets its own SGR, so nothing leaks into the next piece.
    def c(code; text): "\u001b[\(code)m\(text)\u001b[0m";
    # null -> nothing, else "name N%"; bad = 0-100, high is worse. ("label" is a jq keyword.)
    def gauge(name; bad):
      values | name + " " + c(if bad >= 80 then "31" elif bad >= 50 then "2;33" else "2;32" end; "\(.)%");

    (try fromjson catch null | objects) // {}
    # first non-empty string wins
    | (first((try .workspace.current_dir catch null), .cwd, env.PWD | strings | select(. != "")) // ""
        | split("\u0000") | join("")) as $dir   # NUL: bash 4.4+ warns in $()
    | S(.session_id) as $sid
    # Schema: every field the status line reads, and its type
    | { # worktree.* = Claude worktree session; workspace.git_worktree = any linked git worktree
        wt:    (T(.worktree.name) // T(.workspace.git_worktree)),
        from:  T(.worktree.original_branch),
        name:  T(.session_name),
        model: S(.model.display_name),
        ctx:   P(.context_window.used_percentage),
        h5:    P(.rate_limits.five_hour.used_percentage),
        d7:    P(.rate_limits.seven_day.used_percentage),
        hit:   P(.prompt_cache.hit_ratio * 100),
        obs:   B(.prompt_cache.caching_observed),
        warm:  B(.prompt_cache.warm),
        miss:  get(.prompt_cache.misses; numbers | select(. >= 1) | floor) }
    # caching_observed gates the state when present; otherwise .warm decides
    | (if .obs == false then null elif .warm then "warm"
       elif .warm == false or .obs then "cold" else null end) as $state
    # Render: null fields drop out via `values`
    | { dir:  $dir,
        disp: ($dir | tilde | clean),
        sid:  ($sid // ""),
        tail: ([ (.wt | values | c("35"; "wt:" + .)) + (.from | if . then c("2;35"; "<-" + .) else "" end),
                 (.name | values)
               ] | map(" | " + .) | join("")),
        line2: ([ (.model | values | c("2;36"; .)),
                  (.ctx | gauge("ctx"; .)),
                  ([(.h5 | gauge("5h"; .)), (.d7 | gauge("7d"; .))] | select(length > 0) | join(" ")),
                  # needs a hit ratio or a state; high hit ratio is good, so bad = 100 - N
                  (((.hit | gauge("cache"; 100 - .)) // ($state | values | "cache")) as $head
                    | [ $head,
                        ($state | values | c(if . == "warm" then "2;32" else "2" end; .)),
                        (.miss | values | c("2;33"; "\(.) miss"))
                      ] | join(" "))
                ] | join(c("2"; " | "))) }
    # Every value must be a string: @sh on an array emits several words, which eval would run.
    | [to_entries[] | "\(.key)=\(.value | @sh)"] | join(" ")
  ' 2>/dev/null   # remove while editing the jq program: syntax errors are silent otherwise
}

main() {
  local dir='' disp='' sid='' tail='' line2='' branch=''  # initialized: no stale values if eval sets nothing
  # bash 3.2: no namerefs / associative arrays, hence eval
  eval "$(parse_input)"
  # jq failed: fall back to $PWD, with control chars replaced
  # (jq already applied ~; redo it here for the fallback)
  if [[ -z $dir ]]; then
    dir=$PWD disp=${PWD//[[:cntrl:]]/?}
    [[ -n ${HOME-} && ( $disp == "$HOME" || $disp == "$HOME"/* ) ]] && disp="~${disp#"$HOME"}"
  fi
  branch=$(cached_git_segment "$dir" "$sid")

  printf '%s\n' "${C_DIR}${disp}${C_RESET}${branch}${tail}"
  [[ -z $line2 ]] || printf '%s\n' "$line2"
}

main