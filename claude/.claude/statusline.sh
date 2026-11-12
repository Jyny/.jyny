#!/usr/bin/env bash
# Claude Code status line: https://code.claude.com/docs/en/statusline
#   dir | branch[*!] | wt:name[<-orig] | session
#   model | ctx N% | 5h N%/T% 7d N%/T% | cache N% warm|cold [N miss]
#   (N = used, T = window time elapsed)
# Requires bash 3.2+, jq 1.6+, git.

readonly NAME_MAX=40   # max chars for session / worktree names

# Print "<ref>" or "<ref>*!" when dirty; fails outside a git repo. Mirrors oh-my-zsh
# git_prompt_info: branch, else exact tag, else short hash. fsmonitor=false: no repo hooks.
git_info() {
  local git=(git -C "$1" --no-optional-locks -c core.fsmonitor=false) ref
  ref=$("${git[@]}" symbolic-ref --short HEAD 2>/dev/null) \
    || ref=$("${git[@]}" describe --tags --exact-match HEAD 2>/dev/null) \
    || ref=$("${git[@]}" rev-parse --short HEAD 2>/dev/null) \
    || return
  [[ -n $("${git[@]}" status --porcelain --ignore-submodules=dirty 2>/dev/null) ]] && ref+='*!'
  printf '%s' "$ref"
}

# stdin JSON + dir + git_info -> both status lines
render() {
  jq -r --arg dir "$1" --arg git "$2" --argjson max "$NAME_MAX" '
    # SGR codes: dir, git, worktree and model follow oh-my-zsh "dstj"
    { dir: "1;34", branch: "32", dirty: "31", wt: "35", from: "2;35", model: "2;36",
      sep: "2", ok: "2;32", warn: "2;33", crit: "31", cold: "2" } as $C

    # strip control, format (bidi, zero-width) and line/paragraph separators
    | def clean: gsub("[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}]"; "");
      def short: clean | if length > $max then .[:$max - 1] + "…" else . end;
      def c(code): "\u001b[\(code)m\(.)\u001b[0m";
      def tilde: (env.HOME // "") as $h
        | if $h != "" and (. == $h or startswith($h + "/")) then "~" + ltrimstr($h) else . end;
      # "name N%"; bad: 0-100, higher is worse
      def gauge(name; bad): values | round | bad as $b
        | "\(name) " + ("\(.)%" | c(if $b >= 80 then $C.crit elif $b >= 50 then $C.warn else $C.ok end));
      # "name N%/T%": used gauge + share of the window already elapsed
      def limit(name; secs): values | select(.used_percentage != null)
        | (.used_percentage | gauge(name; .))
          + ((.resets_at | numbers | (secs - (. - now)) / secs * 100
              | [., 0] | max | [., 100] | min | round | "/\(.)%" | c($C.sep)) // "");

    # Schema: every field the status line reads
    { dir:   $dir,
      git:   $git,
      wt:    (.worktree.name // .workspace.git_worktree),   # Claude worktree, else linked git worktree
      from:  .worktree.original_branch,
      name:  .session_name,
      model: .model.display_name,
      ctx:   .context_window.used_percentage,
      h5:    .rate_limits.five_hour,
      d7:    .rate_limits.seven_day,
      cache: (.prompt_cache | if .caching_observed == false then null else . end) }

    # Render: absent (null) fields drop out via `values`
    | ([ (.dir | tilde | clean | c($C.dir)),
         (.git | select(. != "")
           | if endswith("*!") then (.[:-2] | clean | c($C.branch)) + ("*!" | c($C.dirty))
             else clean | c($C.branch) end),
         ((.wt | values | "wt:" + short | c($C.wt)) + ((.from | values | "<-" + short | c($C.from)) // "")),
         (.name | values | short)
       ] | join(" | ")),

      ([ (.model | values | clean | c($C.model)),
         (.ctx | gauge("ctx"; .)),
         ([(.h5 | limit("5h"; 5 * 3600)), (.d7 | limit("7d"; 7 * 86400))] | select(length > 0) | join(" ")),
         (.cache | values
           | [ ((.hit_ratio | values | . * 100 | gauge("cache"; 100 - .)) // "cache"),   # high hit = good
               (if .warm then "warm" | c($C.ok) else "cold" | c($C.cold) end),
               (.misses | select(. > 0) | "\(.) miss" | c($C.warn)) ] | join(" "))
       ] | join(" | " | c($C.sep)) | select(. != ""))
  '
}

main() {
  local input dir
  input=$(cat)
  dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
  dir=${dir:-$PWD}
  render "$dir" "$(git_info "$dir")" <<<"$input"
}

main
