# 🪄 zsh-ai

> Stop Googling for command syntax. Just describe what you want.

<img src="https://img.shields.io/github/v/release/matheusml/zsh-ai?label=version&color=yellow" alt="Version"> <img src="https://img.shields.io/badge/dependencies-zero-brightgreen" alt="Zero Dependencies"> <img src="https://img.shields.io/badge/size-<5KB-blue" alt="Tiny Size"> <img src="https://img.shields.io/github/license/matheusml/zsh-ai?color=lightgrey" alt="License">

You know what you want to do, but not the exact command. So you Google it, scroll through Stack Overflow, copy something, adapt it, and hope it works.

**zsh-ai fixes this.** Type what you want in plain English, and get the right command instantly—ready to run. Made a mistake? Type `??` and let AI fix it.

```bash
$ # find all files larger than 100mb modified in the last week
$ find . -type f -size +100M -mtime -7    # ← appears instantly, ready to run

$ git pussh origin main
zsh: command not found: pussh
$ ??
You had a typo: "pussh" should be "push".
$ git push origin main    # ← fixed command, ready to run
```

Works with Anthropic Claude, OpenAI, Google Gemini, Mistral, Grok, Qwen, and local models via Ollama. A single 5KB shell script with zero dependencies.

## Why zsh-ai?

**🎯 Just works** - Type `# what you want` and press Enter. The command appears ready to execute. No copy-paste, no adapting.

**🔍 Explains and fixes errors** - Type `??` after any command to get an explanation. If the error was a typo or wrong flag, the fix appears in your buffer ready to run.

**🧠 Context-aware** - Detects your project type, git status, and current directory. Ask for "run tests" and get `npm test` in a Node project or `pytest` in Python.

**🔒 You stay in control** - Commands appear in your prompt for review before running. Use local Ollama models for complete privacy, or bring your own API keys.

**🪶 Lightweight** - A 5KB shell script. No Python, no Node.js, no package managers. Starts instantly with your shell.

## How It Works

1. **You type** a comment describing what you want: `# compress all images in this folder`
2. **zsh-ai gathers context** about your environment (current directory, git status, project type)
3. **AI generates** the right command for your situation
4. **Command appears** in your prompt, ready to review and run

The command never runs automatically—you always see it first and decide whether to execute it.

## Demo

### Method 1: Comment Syntax (Recommended)
Type `#` followed by what you want to do, then press Enter. It's that simple!

<img src="https://github.com/user-attachments/assets/eff46629-855c-41eb-9de3-a53040bd2654" alt="Method 1 Demo" width="480">


```bash
$ # find all large files modified this week
$ find . -type f -size +50M -mtime -7

$ # kill process using port 3000  
$ lsof -ti:3000 | xargs kill -9

$ # compress images in current directory
$ for img in *.{jpg,png}; do convert "$img" -quality 85 "$img"; done
```

You can also use `?` as an alternative to `#`:

```bash
$ ? find all large files modified this week
$ find . -type f -size +50M -mtime -7
```

---

### Method 2: Explain and Fix (`??`)
After running a command, type `??` to get an explanation. If the error is a typo or bad argument, the corrected command is placed in your buffer.

```bash
# Fix a typo
$ git pussh origin main
zsh: command not found: pussh
$ ??
You had a typo: "pussh" should be "push".
$ git push origin main

# Explain a failed command
$ tar -xvf archive.tgz
tar: archive.tgz: Cannot open: No such file or directory
$ ?? why did this fail
The file archive.tgz does not exist in the current directory.

# Add your own question
$ find . -name '*.log' -mtime +30 -delete
$ ?? what did that just delete?
Deleted all .log files in the current directory tree that were last modified more than 30 days ago.
```

---

### Method 3: Direct Command
Prefer explicit commands? Use `zsh-ai` followed by your natural language request.

<img src="https://github.com/user-attachments/assets/e58f0b99-68bf-45a5-87b9-ba7f925ddc87" alt="Method 2 Demo" width="480">


```bash
$ zsh-ai "find all large files modified this week"
$ find . -type f -size +50M -mtime -7

$ zsh-ai "kill process using port 3000"
$ lsof -ti:3000 | xargs kill -9

$ zsh-ai "compress images in current directory"
$ for img in *.{jpg,png}; do convert "$img" -quality 85 "$img"; done
```

## Quick Start

**1. Install** (Homebrew)
```bash
brew tap matheusml/zsh-ai && brew install zsh-ai
```

**2. Add to your shell**
```bash
echo 'source $(brew --prefix)/share/zsh-ai/zsh-ai.plugin.zsh' >> ~/.zshrc
```

**3. Set your API key** (pick one provider)
```bash
# Anthropic (default)
echo 'export ANTHROPIC_API_KEY="your-key-here"' >> ~/.zshrc

# Or OpenAI
echo 'export OPENAI_API_KEY="your-key-here"' >> ~/.zshrc
echo 'export ZSH_AI_PROVIDER="openai"' >> ~/.zshrc

# Or use local Ollama (free, private)
echo 'export ZSH_AI_PROVIDER="ollama"' >> ~/.zshrc
```

**4. Restart your terminal and try it!**
```bash
# show disk usage for current directory
```

📚 **[Full Installation Guide →](INSTALL.md)** - Other install methods (Oh My Zsh, Antigen, manual) and all provider options

## Documentation

- 📦 **[Installation & Setup](INSTALL.md)** - Detailed installation instructions for all package managers
- 🔧 **[Configuration](INSTALL.md#configuration)** - API keys, providers, and customization options  
- 🚨 **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- 🤝 **[Contributing](CONTRIBUTING.md)** - Help make zsh-ai better!
