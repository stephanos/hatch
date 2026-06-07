use anyhow::Context;
use clap::{CommandFactory, Parser, ValueEnum};
use clap_complete::Shell;
use std::io::{self, Write};

mod engine;

#[derive(Debug, Parser)]
pub struct CompletionsArgs {
    pub(crate) shell: CompletionTarget,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub enum CompletionTarget {
    Bash,
    Elvish,
    Fish,
    #[value(name = "powershell")]
    PowerShell,
    Zsh,
    Carapace,
}

#[derive(Debug, Parser)]
pub struct CompleteArgs {
    #[arg(long)]
    pub(crate) current: usize,
    #[arg(long)]
    pub(crate) with_description: bool,
    #[arg(long, hide = true)]
    pub(crate) with_markers: bool,
    #[arg(trailing_var_arg = true)]
    pub(crate) words: Vec<String>,
}

#[derive(Debug, Parser)]
pub struct CarapaceCompleteArgs {
    #[arg(long)]
    pub(crate) index: usize,
    #[arg(long = "type")]
    pub(crate) _completion_type: Option<String>,
    #[arg(long)]
    pub(crate) _no_space: bool,
    #[arg(long)]
    pub(crate) _ifs: Option<String>,
    #[arg(trailing_var_arg = true)]
    pub(crate) words: Vec<String>,
}

pub fn run(args: CompletionsArgs) -> anyhow::Result<()> {
    let script = match args.shell {
        CompletionTarget::Bash => complete_bash_script(clap_complete_script(Shell::Bash)?),
        CompletionTarget::Zsh => complete_zsh_script(),
        CompletionTarget::Fish => complete_fish_script(),
        CompletionTarget::Elvish => clap_complete_script(Shell::Elvish)?,
        CompletionTarget::PowerShell => clap_complete_script(Shell::PowerShell)?,
        CompletionTarget::Carapace => complete_carapace_spec(),
    };

    let mut stdout = io::stdout();
    stdout.write_all(script.as_bytes())?;
    Ok(())
}

fn clap_complete_script(shell: Shell) -> anyhow::Result<String> {
    let mut command = crate::commands::Args::command();
    let name = command.get_name().to_string();
    let mut output = Vec::new();
    clap_complete::generate(shell, &mut command, name, &mut output);
    String::from_utf8(output).context("failed to generate shell completion script as UTF-8")
}

fn complete_carapace_spec() -> String {
    r#"name: hatch
description: CLI for AI-driven git workspace management
completion:
  positionalany: ["$carapace.bridge.Clap([hatch])"]
"#
    .to_string()
}

fn complete_zsh_script() -> String {
    r#"
#compdef hatch

_hatch() {
    local -a suggestions
    local -a markers
    local -a display_values
    local -a completion_words=("${words[@]}")
    local current_token=""
    local current=$((CURRENT - 1))
    (( current < 0 )) && current=0
    local output
    if (( CURRENT <= ${#completion_words[@]} )); then
        current_token="${completion_words[CURRENT]}"
    fi

    output="$(hatch __complete --with-markers --current "$current" -- "${completion_words[@]}" 2>/dev/null)"
    suggestions=()
    markers=()
    while IFS=$'\t' read -r value desc; do
        [[ -z "$value" ]] && continue
        suggestions+=("$value")
        markers+=("$desc")
    done <<< "$output"
    if [ ${#suggestions[@]} -gt 0 ]; then
        if (( ${#suggestions[@]} == 1 )) && [[ "${suggestions[1]}" == "$current_token" ]]; then
            compstate[insert]=''
            return 1
        fi
        zmodload -i zsh/complist 2>/dev/null
        local ZLS_COLORS="${ZLS_COLORS:+$ZLS_COLORS:}=>*=1;33:=\\?*=1;35:ma=1;33"
        compstate[list]='list force'
        if (( ${#suggestions[@]} == 1 )) && (( current != 0 )) && [[ -n "$current_token" ]]; then
            compstate[insert]=menu
        else
            compstate[insert]=''
        fi
        if (( ${#suggestions[@]} > 1 )); then
            display_values=()
            local index=1
            for value in "${suggestions[@]}"; do
                local display_value="$value"
                if [[ -n "$current_token" && "$value" == *"$current_token"* ]]; then
                    display_value="${value/$current_token/[$current_token]}"
                fi
                if [[ "${markers[index]}" == "ambiguous" ]]; then
                    display_values+=("? $display_value")
                elif [[ "${markers[index]}" == "default" ]]; then
                    display_values+=("> $display_value")
                elif (( index == 1 )); then
                    display_values+=("> $display_value")
                else
                    display_values+=("$display_value")
                fi
                (( index++ ))
            done
            compadd -U -Q -d display_values -a suggestions
        else
            compadd -U -Q -a suggestions
        fi
        return 0
    fi
    if (( current != 0 )) && [[ -n "$current_token" ]]; then
        compstate[insert]=''
        compstate[list]='list force'
        compadd -x "no matches for $current_token"
        return 0
    fi
    return 1
}

if ! whence -w compdef >/dev/null 2>&1; then
    autoload -Uz compinit
    compinit
fi

compdef _hatch hatch
"#
    .to_string()
}

fn complete_fish_script() -> String {
    r#"
function __fish_hatch_complete
  set -l words (commandline -opc)
  if test -z "$words"
    return 0
  end

  set -l current (math (count $words) - 1)
  if test $current -lt 0
    set current 0
  end
  set -l output (hatch __complete --with-description --current $current -- $words 2>/dev/null)
  if test -n "$output"
    for line in $output
      printf '%s\n' $line
    end
  end
end

complete -c hatch -f -a "(__fish_hatch_complete)"
complete -c hatch -f -s h -l help -d 'Print help'
"#
    .to_string()
}

pub(crate) fn run_complete_command(words: &[String], current: usize) -> anyhow::Result<()> {
    for completion in engine::complete_candidates(words, current) {
        println!("{}", completion.value);
    }
    Ok(())
}

pub(crate) fn run_complete_command_with_description(
    words: &[String],
    current: usize,
) -> anyhow::Result<()> {
    for completion in engine::complete_candidates(words, current) {
        match completion.description {
            Some(description) => println!("{}\t{}", completion.value, description),
            None => println!("{}", completion.value),
        }
    }
    Ok(())
}

pub(crate) fn run_complete_command_with_markers(
    words: &[String],
    current: usize,
) -> anyhow::Result<()> {
    for completion in engine::complete_candidates(words, current) {
        match completion.marker {
            Some(marker) => println!("{}\t{}", completion.value, marker),
            None => println!("{}", completion.value),
        }
    }
    Ok(())
}

fn complete_bash_script(mut script: String) -> String {
    let marker = "_hatch() {";
    if let Some(pos) = script.find(marker) {
        script.replace_range(pos..pos + marker.len(), "_hatch_clap() {");
    }
    script.push_str(
        r#"

_hatch() {
    local output
    local -a suggestions=()
    local current=$((COMP_CWORD - 1))
    local cur="${COMP_WORDS[COMP_CWORD]:-}"
    local -a words=("${COMP_WORDS[@]:1}")
    if output="$(hatch __complete --current "$current" -- "${words[@]}" 2>/dev/null)"; then
        if [ -n "$output" ]; then
            while IFS= read -r line; do
                suggestions+=("$line")
            done <<< "$output"
        fi
    fi
    if [ ${#suggestions[@]} -ne 0 ]; then
        COMPREPLY=("${suggestions[@]}")
        return 0
    fi
    _hatch_clap "$@"
}

complete -o nosort -o bashdefault -o default -F _hatch hatch
"#,
    );
    script
}
