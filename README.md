# Slidict

Generate presentation source files from a simple conversation.

Slidict is a CLI tool that helps you turn rough ideas into presentations through AI-guided conversations.

Unlike traditional slide generators, Slidict focuses on communication before slide creation.

## Features

- Interactive CLI conversation
- Generate slides for Slidev, Marp, Asciidoctor Reveal.js, and other OSS presentation frameworks
- Local-first MVP implemented in Ruby
- Built-in Sinatra server for browsing generated slides from `public/`
- OpenAI Compatible API support, so you can point Slidict at OpenAI, Ollama, LM Studio, vLLM, or any other server implementing the same `/chat/completions` endpoint
- Presentation structure linter: checks whether a Markdown/Asciidoc deck's *structure* (not its looks) will land with an audience

## Requirements

- Ruby 3.1 or later

## Usage

Run the executable directly from this repository:

```bash
bin/slidict
```

Slidict asks a few questions and generates presentation source files. For example, this creates a Marp Markdown deck:

```bash
$ bin/slidict --framework marp

What would you like to talk about?
> PDF Difference Monitoring Service
How long is the presentation?
> 5 minutes
Who is the audience?
> Engineering managers
What should the audience remember or do?
> Approve an MVP pilot
Created public/001.md
```

You can also provide answers non-interactively:

```bash
bin/slidict \
  --topic "PDF Difference Monitoring Service" \
  --duration "5 minutes" \
  --audience "Engineering managers" \
  --goal "Approve an MVP pilot" \
  --framework asciidoctor-revealjs \
  --output slides.adoc
```

Add `--publish` to also save the generated slides to slidict.io as a draft (requires
`slidict auth` first). Pass `--slide-id` to edit an existing draft instead of creating a
new one:

```bash
# Create a new draft on slidict.io from the generated slides
bin/slidict --topic "PDF Difference Monitoring Service" --duration "5 minutes" \
  --audience "Engineering managers" --goal "Approve an MVP pilot" --publish

# Edit an existing draft (slide #42) instead of creating a new one
bin/slidict --topic "PDF Difference Monitoring Service" --duration "5 minutes" \
  --audience "Engineering managers" --goal "Approve an MVP pilot" --slide-id 42
```

## Output files

Choose the framework and output path that match the presentation tool you want to use. If you omit `--output`, Slidict writes under `public/` with the next sequential file name. Use `--filename` to choose the relative file name under `public/`; Slidict appends the framework extension when the name has no extension.

```bash
# Choose a served file name under public/
bin/slidict --filename product-demo/slides --topic "Product Demo"
```

```text
Slidev                  -> public/001.md, public/002.md, ...
Marp                    -> public/001.md, public/002.md, ...
Asciidoctor Reveal.js   -> public/001.adoc, public/002.adoc, ...
```

## Commands

### `slidict auth`

Authenticates the CLI with your GitHub account via the device code flow and saves a
CLI access token to `~/.config/slidict/credentials.json`.

```bash
bin/slidict auth
```

### `slidict slides`

Manage your slides on slidict.io using the CLI access token saved by `slidict auth`.

```bash
bin/slidict slides list [--page N]
bin/slidict slides show <id>
bin/slidict slides create [--title TEXT] [--body TEXT | --file PATH] [--body-format asciidoc|markdown] [--visibility public|unlisted|group_only]
bin/slidict slides edit <id> [--title TEXT] [--body TEXT | --file PATH] [--body-format asciidoc|markdown] [--visibility public|unlisted|group_only]
```

- `create` and `edit` always save the slide as a draft. Publishing requires going through
  the moderation flow on the Web UI; the CLI cannot publish a slide.
- `edit` only works on slides that are still drafts; editing an already-published slide
  must be done from the Web UI.
- `create`/`edit` are rate limited to once per minute per user.

Run `bin/slidict slides -h` for the full list of options.

### `slidict serve`

Serve generated slide files from the local `public/` directory with Sinatra. The top
page lists Markdown and Asciidoc slide files below `public/`, so you can organize
decks in subdirectories such as `public/product-demo/slides.md`. Any arguments
after `serve` are passed through to Sinatra.

```bash
bin/slidict serve -p 4567 -o 0.0.0.0
```

`bin/slidict --publish` and `--slide-id` (see [Usage](#usage)) wrap this same `create`/`edit`
behavior so you can save the slides you just generated straight to slidict.io.

### `slidict lint`

Diagnoses whether a Markdown or Asciidoc slide deck has a structure an audience can
actually follow -- not whether it looks nice. Diagnosis only; it does not rewrite the
file. Requires an LLM endpoint (see [Configuration](#configuration)).

```bash
bin/slidict lint talk.md --llm-base-url http://localhost:11434/v1 --llm-api-key ollama --llm-model llama3
```

```text
[warning] Slide 3: this slide's main point is unclear
[warning] Slide 5: "MCP" is used without first explaining it
[info] Slide 8: the closing slide is weak; consider adding a one-sentence takeaway for the audience
```

It checks six things across the whole deck:

1. Is the audience clear?
2. Can the overall point be stated in one sentence?
3. Does the deck flow background → problem → solution → result/learning?
4. Is any single slide overloaded with information?
5. Is jargon used without first explaining it?
6. Does the closing slide give the audience a concrete takeaway?

The deck format (`markdown` or `asciidoc`) is auto-detected from the file extension;
override it with `--format`. Run `bin/slidict lint -h` for the full list of options.

## Configuration

Slidict generates slides with an LLM through any OpenAI Compatible API. Configure the
target endpoint with environment variables or CLI flags (flags take precedence):

| Environment variable    | CLI flag         | Default        |
| ------------------------ | ---------------- | -------------- |
| `SLIDICT_LLM_BASE_URL`    | `--llm-base-url` | _(none)_       |
| `SLIDICT_LLM_API_KEY`     | `--llm-api-key`  | _(none)_       |
| `SLIDICT_LLM_MODEL`       | `--llm-model`    | `gpt-4o-mini`  |

If no `llm-base-url` is configured, Slidict uses its built-in slide template and never
calls an LLM. Once a `llm-base-url` is set, Slidict always calls that endpoint; if the
request fails, Slidict reports the error and exits without writing a file (no fallback).
You can force the template even when a base URL is configured with `--no-llm`.

Examples:

```bash
# OpenAI
export SLIDICT_LLM_BASE_URL=https://api.openai.com/v1
export SLIDICT_LLM_API_KEY=sk-...
bin/slidict --topic "PDF Difference Monitoring Service" --duration "5 minutes" \
  --audience "Engineering managers" --goal "Approve an MVP pilot"

# Ollama (running locally, OpenAI Compatible API)
bin/slidict --llm-base-url http://localhost:11434/v1 --llm-api-key ollama --llm-model llama3

# LM Studio (running locally, OpenAI Compatible API)
bin/slidict --llm-base-url http://localhost:1234/v1 --llm-api-key lm-studio --llm-model local-model
```

## Philosophy

Slidict helps you communicate ideas, not just create slides.

Many presentation tools focus on layouts, themes, and visual design.

Slidict focuses on the message.

Before generating slides, Slidict helps you:

- Clarify your message
- Build a compelling narrative
- Focus on what matters
- Create presentations people remember

```text
Idea
 ↓
Conversation
 ↓
Story
 ↓
Slides
```

We optimize for communication, not decoration.

## Roadmap

- [x] Interactive CLI
- [x] Slide generation
- [x] OpenAI Compatible API support (configurable base URL, so Ollama, LM Studio, and other compatible servers work out of the box)
- [x] Presentation structure linter (`slidict lint`)

## License

MIT

## Presentation methods

Slidict supports data-driven presentation methods. A method defines the narrative
technique, slide roles, AI instructions, and review checklist in YAML, while the Ruby
gem only loads, validates, and applies that data.

```bash
bin/slidict new --method prep --topic "New onboarding flow"
bin/slidict --method scqa --topic "Database migration plan"
bin/slidict --method pyramid --topic "FY roadmap recommendation"
bin/slidict list-methods
bin/slidict show-method scqa
```

Built-in methods currently include SCQA, PREP, and Pyramid Principle.

### Method architecture

The method system is intentionally data-first:

1. YAML files live in `data/slidict/methods/`.
2. `Slidict::PresentationMethodRegistry` discovers built-in files and plugin-provided files.
3. `Slidict::PresentationMethod` validates each YAML document and maps it to Ruby objects.
4. `Slidict::Deck` uses the method's slide roles as the built-in non-LLM outline.
5. `Slidict::Llm::Client` injects the method description, slide roles, and AI instructions into the generation prompt.

This keeps contribution review small: a new built-in method is usually one YAML file and no Ruby code.

### Directory structure

```text
data/slidict/methods/
  prep.yml
  pyramid.yml
  scqa.yml
lib/slidict/presentation_method.rb
```

For 100+ methods, keep one method per file and use stable lowercase IDs such as
`scqa`, `prep`, `pyramid`, or `problem-solution`. Categories are free-form labels
that can later drive filtering without changing the file layout.

### YAML schema

Each method file is a single YAML mapping:

```yaml
id: scqa
name: SCQA
category: narrative
description: Situation, Complication, Question, Answer structure for building a clear business narrative.
locale: en
suitable_for:
  - Strategy updates
  - Problem-solving proposals
slides:
  - title: Situation
    role: Establish the shared context the audience already recognizes.
    instructions: Describe the current state with concrete facts.
ai_instructions:
  - Use the SCQA sequence exactly.
review_checklist:
  - Does the situation establish common ground?
references:
  - title: The Pyramid Principle
    author: Barbara Minto
```

Required fields are `id`, `name`, `category`, `description`, `suitable_for`,
`slides`, `ai_instructions`, and `review_checklist`. `references` and `locale` are
optional; `locale` defaults to `en`. Every slide entry requires `title`, `role`, and
`instructions`.

### Ruby class design

- `Slidict::PresentationMethod` represents one method definition.
- `Slidict::MethodSlide` represents each slide role.
- `Slidict::PresentationMethodRegistry` loads built-in YAML files and plugin YAML files.
- `Slidict::Deck` accepts an optional `presentation_method` and turns method slide roles into a local template when `--no-llm` is used or no LLM is configured.

Validation happens at load time with `YAML.safe_load_file`. Slidict checks required
fields, requires lowercase method IDs (`a-z`, `0-9`, and `-`), and verifies that each
slide role has the required fields.

### CLI design

- `--method ID` applies a method to generated slides.
- `list-methods` prints every discovered method.
- `show-method ID` prints a method's description, use cases, slide roles, and review checklist.

### Plugin design

External gems can distribute methods without changing Slidict itself. A plugin gem only
needs to place YAML files under `lib/slidict/methods/*.yml` so RubyGems can expose them
through `Gem.find_files`.

Example plugin layout:

```text
slidict-methods-product/
  lib/slidict/methods/product-demo.yml
  slidict-methods-product.gemspec
```

After the plugin gem is installed, Slidict automatically includes those YAML files in
`list-methods`, `show-method`, and `--method` lookup.

### Future localization

Method files include a `locale` field. The recommended future shape is one file per
localized method, for example `scqa.en.yml` and `scqa.ja.yml`, with the same method ID
plus locale-aware lookup. Keeping all user-facing text in YAML means translations can be
reviewed independently from Ruby changes.

### OSS contribution workflow

To propose a new presentation method:

1. Copy an existing YAML file in `data/slidict/methods/`.
2. Change `id`, `name`, `category`, `description`, `suitable_for`, `slides`, `ai_instructions`, and `review_checklist`.
3. Add `references` when useful.
4. Run `bundle exec rspec` and `bundle exec rubocop`.
5. Open a PR with the method file and a short explanation of the communication technique.
