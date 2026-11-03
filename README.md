# Witches and Warlocks

Godot **4.7** multiplayer game. The main scene is `scenes/bootstrap.tscn`, which either starts a dedicated server or loads the lobby client.

## Requirements

- [Godot 4.7](https://godotengine.org/download/) (matches `project.godot`)

## How bootstrap chooses mode

- **Dedicated server** if the `dedicated_server` feature is on, or user arg `--dedicated` is present  
  → starts `NetworkManager` on port **7000**
- **Otherwise client** → loads `scenes/lobby.tscn`

`--` separates Godot’s own flags from game user args (`OS.get_cmdline_user_args()`).

## Run server + client together

### Editor (GUI)

1. Open this folder as a Godot project.
2. **Debug → Customize Run Instances…**
3. Set **instance count** to **2**.
4. Configure the instances:
   - **Instance 1 (server):**  
     - **Arguments:** `-- --dedicated`  
     - *or* **Feature tags:** `dedicated_server`  
     - optional: `--headless` if you don’t want a server window
   - **Instance 2 (client):** leave args / tags empty
5. Press **F5** (Play). Both start at once.
6. In the **client** window, join `127.0.0.1` (or leave the address empty — that’s the default).

When you only want a single client again, set instances back to **1**.

**Client only (default):** instances = 1, no special args, then **F5**.

### Command line (CLI)

From the project root. If `godot` isn’t on your `PATH`, use the full path to your Godot 4.7 binary.

**Server + client in one go:**

```bash
godot --path . --headless -- --dedicated &
godot --path .
```

**Two terminals** (clearer logs):

```bash
# terminal 1 — dedicated server
godot --path . --headless -- --dedicated

# terminal 2 — client
godot --path .
```

**Client only:**

```bash
godot --path .
```

**Dedicated server only:**

```bash
godot --path . --headless -- --dedicated
```

Extra clients: run `godot --path .` again.

### In the lobby

1. Join `127.0.0.1` (default if left blank).
2. Pick a class, ready up, start when the lobby leader can.
