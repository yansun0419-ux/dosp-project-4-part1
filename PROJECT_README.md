# DOSP Project 4 Part 1 - Reddit Clone

A Reddit-like social media engine built with Gleam using the Actor Model.

## Quick Start

```sh
# Install dependencies
gleam deps download

# Build the project  
gleam build

# Run the simulation (100 users, 20 subreddits)
gleam run

# Run tests
gleam test
```

## What This Project Does

This project implements a Reddit-like engine with:
- User registration and karma tracking
- Subreddit creation and membership
- Posts with upvote/downvote
- Hierarchical comments
- Direct messaging
- Feed generation

Plus a simulator that:
- Creates hundreds of concurrent users
- Simulates realistic social network behavior with Zipf distribution
- Generates random posts, votes, and subscriptions
- Reports performance metrics

## Architecture

Built using the **Actor Model** with Gleam's OTP:
- **Single Engine Actor**: Manages all Reddit state
- **Multiple Client Actors**: Simulate independent users
- **Message Passing**: All communication via typed messages
- **No Shared State**: Pure functional, immutable data

## Files

- `src/types.gleam` - Core data types
- `src/engine.gleam` - Reddit engine actor (600+ lines)
- `src/simulator.gleam` - Client simulator with Zipf distribution
- `src/dosp_project_4_part1.gleam` - Main entry point
- `test/dosp_project_4_part1_test.gleam` - Test suite
- `REPORT.md` - Detailed documentation

## Configuration

Edit `src/dosp_project_4_part1.gleam` to change simulation parameters:

```gleam
let config = SimulationConfig(
  num_clients: 100,        // Number of users
  num_subreddits: 20,      // Number of subreddits
  num_posts_per_user: 5,   // Actions per user
  zipf_param: 1.5,         // Zipf distribution (1.0-2.0)
  simulation_duration_ms: 5000,
)
```

## Test with More Users

```gleam
let config = SimulationConfig(
  num_clients: 1000,       // 1000 users!
  num_subreddits: 100,
  num_posts_per_user: 10,
  zipf_param: 2.0,
  simulation_duration_ms: 10000,
)
```

## Sample Output

```
=== Reddit Clone - Distributed Systems Project ===

Starting Reddit Engine...
Engine started successfully!

=== Starting Reddit Clone Simulation ===
Clients: 100
Subreddits: 20
Duration: 5000 ms

Creating subreddits...
Created 20 subreddits

Registering users and starting clients...
Started 100 client actors

Running simulation...
Simulation complete!

=== Final Statistics ===
Total Users: 101
Online Users: 101
Total Subreddits: 20
Total Posts: 150+
Total Comments: 50+
Total Messages: 30+
Actions/second: 100.0

=== Simulation Complete ===
```

## Requirements Met

✅ Actor Model implementation  
✅ Separate engine and client processes  
✅ User registration  
✅ Subreddit create/join/leave  
✅ Posts with text content  
✅ Hierarchical comments  
✅ Upvote/downvote + karma  
✅ Feed generation  
✅ Direct messaging  
✅ Zipf distribution for members  
✅ Multiple concurrent clients  
✅ Online/offline simulation  
✅ Performance metrics  

## Technologies

- **Gleam** - Type-safe functional language
- **Erlang/OTP** - Actor model runtime
- **BEAM VM** - Concurrent execution

## Report

See `REPORT.md` for detailed implementation documentation.
