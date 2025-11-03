# DOSP Project 4: Part I - Gleam Reddit Engine

This project implements a distributed, actor-based engine for a Reddit-like service using the [Gleam](https://gleam.run/) programming language on the BEAM (Erlang VM).

## Group Members

- Forrest Yan Sun
- Harsh Soni

## Project Overview

The system consists of two main parts:
1.  **The Engine**: A set of concurrent actors that manage the state of the Reddit service. This includes a central `Registry` actor for user management and message routing, and dynamic `Subreddit` actors for handling posts, comments, and votes.
2.  **The Simulator**: A collection of 100+ concurrent client actors designed to stress-test the engine by simulating a wide range of user behaviors at high volume.

The architecture leverages the actor model to achieve high concurrency and fault tolerance, with over 120 independent processes running simultaneously during the simulation.

## Requirements

- [Erlang/OTP](https://www.erlang.org/downloads) (25.0 or later)
- [Gleam](https://gleam.run/getting-started/) (1.0.0 or later)

## How to Build

Navigate to the project root directory and run the following command to compile the project:

```sh
gleam build
```

## How to Run the Simulation

To run the performance simulation, execute the following command from the project root:

```sh
gleam run
```

The simulation will start 100 client actors, each attempting 1,000 actions over a 10-second period. At the end of the run, it will print a detailed performance report to the console.

For a cleaner output focusing only on the final statistics, you can pipe the output:

```sh
gleam run 2>/dev/null | grep -A 25 "Performance Statistics"
```

## Project Structure

- `src/dosp_project_4_part1.gleam`: The main entry point for the application, responsible for setting up and running the simulation.
- `src/registry.gleam`: The central registry actor. It manages user registration, subreddit actor routing, and the direct messaging system.
- `src/subreddit_actor.gleam`: The actor for individual subreddits. It handles all content-related operations like posts, comments, votes, and karma calculation.
- `src/simulator.gleam`: The client actor implementation. It simulates user behavior by sending messages to the engine based on a weighted, random distribution of actions.
- `src/types.gleam`: Contains all the shared data types and message definitions used across the system.
- `gleam.toml`: The project's manifest file, defining dependencies and metadata.
