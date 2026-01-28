# Goose Recipe File Specification  
*(Complete ­— including Extension Configuration)*

> A Goose **Recipe** is a portable JSON / YAML file that turns Goose into a
> fully-featured, pre-configured agent.  
> This document is the **single, canonical reference** for every field you can
> put in that file.

---

## 1. Top-Level Schema

| Field            | Type                           | Req. | Default | Purpose                                                                                                     |
|------------------|--------------------------------|------|---------|-------------------------------------------------------------------------------------------------------------|
| `version`        | `string` (semver)              | No   | `"1.0.0"` | Version of the **file format** (not your agent).                                                             |
| `title`          | `string`                       | Yes  | –       | Short name shown in UI.                                                                                     |
| `description`    | `string`                       | Yes  | –       | One-to-three sentences explaining what the agent does.                                                      |
| `instructions`   | `string`                       | *⇠*  | –       | System / “role” message injected into the model.                                                            |
| `prompt`         | `string`                       | *⇠*  | –       | First assistant message visible to the user.                                                                |
| `extensions`     | [`ExtensionConfig[]`](#4-extension-configuration) | No | – | Extra toolsets the agent can call.                                                                          |
| `context`        | `string[]`                     | No   | –       | Additional snippets appended to the chat context.                                                           |
| `settings`       | [`Settings`](#32-settings)     | No   | –       | Model/provider/temperature overrides for this recipe.                                                       |
| `activities`     | `string[]`                     | No   | –       | UI “pills” (quick-pick actions) displayed when the recipe loads.                                            |
| `author`         | [`Author`](#31-author)         | No   | –       | Info about the recipe creator.                                                                              |
| `parameters`     | [`RecipeParameter[]`](#33-parameters) | No | – | Structured inputs the user must (or may) supply before first run.                                           |

*⇠ At least **one of** `instructions` **or** `prompt` is required.*

---

## 2. Quick Examples

<details>
<summary>Minimal</summary>

```json
{
  "title": "Hello-World Bot",
  "description": "Responds with a friendly greeting",
  "instructions": "Always greet the user cheerfully."
}
```
</details>

<details>
<summary>Full-featured</summary>

```jsonc
{
  "version": "1.2.0",
  "title": "Weekly Report Generator",
  "description": "Summarises Jira issues, writes Markdown, then emails it.",
  "prompt": "Hi! Paste your Jira board URL and due date.",
  "extensions": [
    {
      "type": "sse",
      "name": "jira",
      "uri": "https://jira.example.com/sse",
      "env_keys": ["JIRA_TOKEN"],
      "timeout": 30
    },
    {
      "type": "builtin",
      "name": "email"
    }
  ],
  "settings": { "goose_provider": "openai", "goose_model": "gpt-4o-mini", "temperature": 0.3 },
  "activities": ["Generate", "Refine", "Send"],
  "author": { "contact": "alice@example.com" },
  "parameters": [
    { "key": "jira_board", "input_type": "string", "requirement": "required", "description": "Full board URL" },
    { "key": "due_date",   "input_type": "date",   "requirement": "user_prompt", "description": "When is it due?" }
  ]
}
```
</details>

---

## 3. Nested Objects

### 3.1 Author

| Field      | Type   | Req. | Description                             |
|------------|--------|------|-----------------------------------------|
| `contact`  | string | No   | Email, website, or social handle.       |
| `metadata` | string | No   | Free-form; licence, acknowledgements…   |

### 3.2 Settings

| Field            | Type   | Req. | Description                                                 |
|------------------|--------|------|-------------------------------------------------------------|
| `goose_provider` | string | No   | Provider slug (`openai`, `anthropic`, `local`, …).          |
| `goose_model`    | string | No   | Exact model name (`gpt-4o`, `claude-3.5-sonnet`, …).        |
| `temperature`    | float  | No   | 0 – 2.0. Higher ⇒ more creative.                            |

### 3.3 Parameters

| Field         | Type                                                       | Req. | Description                                              |
|---------------|------------------------------------------------------------|------|----------------------------------------------------------|
| `key`         | string                                                     | Yes  | Identifier; appears as `{{key}}` placeholder.            |
| `input_type`  | `"string" \| "number" \| "boolean" \| "date" \| "file"` | Yes  | Controls input widget in UI.                             |
| `requirement` | `"required" \| "optional" \| "user_prompt"`                | Yes  | `user_prompt` shows a blocking dialog on first run.      |
| `description` | string                                                     | Yes  | Help-text.                                               |
| `default`     | string                                                     | No   | Pre-filled value.                                        |

---

## 4. Extension Configuration

`extensions` is an **array** of objects; each object must contain a top-level
`type` field that tells Goose how to launch or locate the extension.

### 4.1 Common Fields (present on some or all variants)

| Field        | Type      | Applies to | Description                                                                        |
|--------------|-----------|------------|------------------------------------------------------------------------------------|
| `name`       | string    | all        | Unique slug (used in prompts & logging).                                           |
| `timeout`    | integer (s) | all     | Optional RPC timeout in **seconds**. Default: goose global default (60 s).         |
| `bundled`    | boolean   | all        | If `true`, extension ships with Goose; UI may hide advanced settings.              |
| `description`| string    | sse, stdio | Human description for listing / help.                                              |
| `envs`       | object    | sse, stdio | Map of **explicit** environment variables passed to the extension.                 |
| `env_keys`   | string[]  | sse, stdio | List of **allowed pass-through** env-var names to copy from the user environment.  |

> Security: Certain env-vars are **blocked** (e.g. `PATH`, `LD_PRELOAD`, `DYLD_*`);
> any attempt to set them is ignored with a warning.

### 4.2 Variant-specific Schemas

| `type` value | Extra Required Fields                              | Purpose / Transport                                                                          |
|--------------|----------------------------------------------------|----------------------------------------------------------------------------------------------|
| `sse`        | `uri` (string, URL)                                | Connects to an **MCP server** over **Server-Sent Events**.                                   |
| `stdio`      | `cmd` (string), `args` (string[])                  | Launches a child process and speaks MCP over **stdin/stdout**.                               |
| `builtin`    | *(none)*                                           | Enables an extension compiled directly into Goose itself.                                    |
| `frontend`   | `tools` ([`Tool`](https://docs.rs/mcp-core/latest/mcp_core/tool/struct.Tool.html)[]),<br>`instructions?` (string) | Declares tools implemented in the **front-end** (Electron) rather than in Rust.              |

### 4.3 Examples

<details>
<summary>SSE</summary>

```json
{
  "type": "sse",
  "name": "my_vector_search",
  "uri": "http://localhost:8008/sse",
  "description": "Embeddings & semantic search",
  "timeout": 20,
  "env_keys": ["VECTOR_API_KEY"]
}
```
</details>

<details>
<summary>STDIO</summary>

```json
{
  "type": "stdio",
  "name": "python_image_magic",
  "cmd": "/usr/local/bin/python",
  "args": ["image_tools.py"],
  "envs": { "PYTHONUNBUFFERED": "1" },
  "timeout": 45
}
```
</details>

<details>
<summary>Builtin</summary>

```json
{ "type": "builtin", "name": "filesystem" }
```
</details>

<details>
<summary>Frontend</summary>

```json
{
  "type": "frontend",
  "name": "safari_automation",
  "tools": [
    {
      "name": "open_url",
      "description": "Opens a URL in Safari",
      "parameters": ["url"]
    }
  ],
  "instructions": "Use open_url only for http(s) links."
}
```
</details>

---

## 5. Validation Rules

1. `title`, `description`, and `instructions` **or** `prompt` are mandatory.
2. Each `extensions[*].name` must be unique within the recipe.
3. Duplicate `parameters[*].key` values are invalid.
4. `temperature` must be 0 – 2 inclusive if present.
5. Unknown fields are ignored but may trigger warnings.

---

## 6. File Naming & Loading

Suggested pattern:

```
<agent-name>.recipe.json   # or .recipe.yaml
```

Load via Goose Desktop (“Load Recipe…”) or CLI:

```bash
goose run path/to/my.recipe.json
```

---

## 7. Cheat-sheet

| Goal                               | Minimum Fields to set                                                           |
|------------------------------------|---------------------------------------------------------------------------------|
| Plain chat agent                   | `title`, `description`, `instructions`                                          |
| Show a starter message             | + `prompt`                                                                      |
| Use extra tools (e.g. web scrape)  | + `extensions` (pick variant, fill required fields)                             |
| Collect user input first           | + `parameters`                                                                  |
| Force a specific model & style     | + `settings.goose_model`, `settings.temperature`                                |

---

**That’s everything** you need to craft, validate, and distribute Goose Recipes—extensions included. Happy hacking!
