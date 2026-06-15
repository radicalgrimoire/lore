The client is still an early draft so the readme is basic and to the point because it will likely change.

# Example Commands

```
// Create a fresh copy of an empty repo for the client to use before every command
lore clone <repository url>/<repository>

// Run a sequence of commands on the repo
lore-chaos-client chaos -r ".\ChaosPlayground" -i 1000 --seed 1000 --offline

// Run a sequence of commands on the repo, waiting for the user to hit enter between each
lore-chaos-client chaos -r ".\ChaosPlayground" -i 1000 --seed 1000 --offline --user-progressed

// Run sequences of commands on the repo from 16 threads in parallel
lore-chaos-client parallel -r ".\ChaosPlayground" --runners 16 --time-limit-mins 10 --seed 1000 --offline

// Run sequences of commands on the repo from 16 threads in parallel with a randomly generated RNG seed
lore-chaos-client parallel -r ".\ChaosPlayground" --runners 16 --time-limit-mins 10 --offline
```

# Instructions

## Setup

Ensure you have a fresh Lore repo. I keep one empty to be able to freshly clone each time.

```
lore clone <repository url>/<repository>
```

## Running

### Single threaded

The subcommand `chaos` runs random commands on the repo in a single thread.

Options:

- repository_path: Where the Lore repo is
- iterations: Limit how many operations to perform
- time-limit-mins: Limit how long to run
- dry_run: Print the steps without running any Lore commands
- offline: Pass the offline flag to Lore
- seed: RNG seed to use
- user-progressed: Wait for the user to hit enter between each command

So a command will look like

```
lore-chaos-client chaos -r ".\ChaosPlayground" -i 1000 --seed 1000 --offline
```

### Multi threaded

The subcommand `parallel` runs random commands simultaneously from multiple threads,
with one thread making mutable changes and the rest being read only.

Options:

- repository_path: Where the Lore repo is
- iterations: Limit how many operations to perform
- runners: Number of threads to run in parallel
- time-limit-mins: Limit how long to run
- offline: Pass the offline flag to Lore
- seed: RNG seed to use

So a command will look like

```
lore-chaos-client parallel -r ".\ChaosPlayground" --runners 16 --time-limit-mins 10 --seed 1000 --offline
```

## Logging

Lore itself will print to the console.

In addition, WARN and higher events will be written to the console while INFO and higher events will be written to a
file called `chaos_client.log`.

`--log_file=<file name>` can be used to log to a different file.

`--log_to_console` will cause INFO and higher events to also be written to the console.
