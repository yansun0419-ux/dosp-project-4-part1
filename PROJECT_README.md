# DOSP Project 4 Part 1 - Reddit Clone Engine

A distributed Reddit-like social media engine built with Gleam using the Actor Model (OTP).

## Quick Start

```sh
# Install dependencies
gleam deps download

# Build the project  
gleam build

# Run the simulation (100 users, 20 subreddit actors, 5000 operations)
gleam run
```

## What This Project Does

This project implements a **distributed Reddit clone engine** with multiple independent actors:

### Core Features
- **User registration** with karma tracking
- **Subreddit creation** (dynamic actor spawning)
- **Post creation** with upvote/downvote
- **Hierarchical comment system** (comment on comments)
- **Direct messaging** between users
- **Personalized feed** generation

### Realistic Simulator
- **100 concurrent client actors**
- **True Zipf distribution** (popular subreddits get more traffic)
- **Disconnect/reconnect** simulation (5% users go offline)
- **Reposting** from hot posts pool (15% of posts)
- **Realistic voting** (users vote from feed, not blind)

## Architecture: Distributed Multi-Actor Design

### Understanding "Single-Engine Process"

The assignment suggests "a single-engine process." **Our interpretation**: A unified service interface (logical single engine), not a literal single Actor.

### Core Components

#### 1. Registry Actor - Unified Entry Point
**File**: `registry.gleam` (235 lines)

- Acts as the **sole external interface** for the entire Reddit engine
- Manages global user registration
- **Dynamically creates** Subreddit Actors on demand
- Routes requests to appropriate Subreddit Actors
- Handles direct messages between users

#### 2. Subreddit Actors - Independent Content Engines  
**File**: `subreddit_actor.gleam` (285 lines per actor)

- **ONE independent Actor per Subreddit** (complete isolation)
- Handles posts, comments, votes within that subreddit
- **No shared state** between Subreddit Actors
- True parallel processing (20 actors = 20 concurrent processes)

#### 3. Client Actors - User Simulation
**File**: `simulator.gleam` (739 lines)

- 100 concurrent client actors
- Each performs 50 independent actions
- Realistic patterns: Zipf distribution, disconnects, reposts, realistic voting

#### 4. Type System - Message Definitions
**File**: `types.gleam` (230 lines)

- Type-safe message passing
- Immutable data structures
- `RegistryMessage` (14 types) + `SubredditMessage` (11 types)

### Why Multiple Actors?

✅ **True Distribution**: Registry doesn't process posts, each Subreddit Actor operates independently  
✅ **Fault Isolation**: One subreddit failure doesn't affect others  
✅ **Horizontal Scalability**: N subreddits = N concurrent actors  
✅ **No Bottleneck**: Registry only routes, doesn't process content  
✅ **Satisfies "Single Engine"**: From client perspective, there's only one unified service  

## File Structure

```
src/
├── types.gleam              # Data types and message definitions (230 lines)
├── registry.gleam           # Registry Actor - unified entry point (235 lines)  
├── subreddit_actor.gleam    # Subreddit Actor - independent engine (285 lines)
├── simulator.gleam          # Client simulator with realistic behavior (739 lines)
└── dosp_project_4_part1.gleam  # Main entry point (55 lines)
```

**Total**: ~1,544 lines of production code

## Configuration

Edit `src/dosp_project_4_part1.gleam` to change simulation parameters:

```gleam
let config = SimulationConfig(
  num_clients: 100,              // Number of concurrent client actors
  num_subreddits: 20,            // Number of Subreddit Actors (each independent)
  num_posts_per_user: 50,        // Actions per client
  zipf_param: 1.5,               // Zipf distribution (higher = more skewed)
  simulation_duration_ms: 30_000, // 30 seconds
)
```

### Test with Larger Scale

```gleam
let config = SimulationConfig(
  num_clients: 1000,       // 1000 concurrent users
  num_subreddits: 100,     // 100 independent Subreddit Actors
  num_posts_per_user: 50,
  zipf_param: 2.0,
  simulation_duration_ms: 60_000,
)
```

## Expected Output

```
=== Reddit Clone - Distributed Systems Project ===
=== Multi-Actor Distributed Architecture ===

Starting Registry Actor...
Registry started successfully!
Ready to spawn Subreddit Actors...

⚡ DISTRIBUTED ACTOR SYSTEM ⚡
Clients: 100 | Subreddit Actors: 20 | Total Actions: 5,000
Architecture: Registry + Multiple Subreddit Actors

Creating subreddits...
Created 20 subreddits (20 independent Actors)

Registering users and starting clients...
Started 100 client actors

Running distributed simulation...
Processing actions across distributed actors...

=== 🎯 Performance Statistics 🎯 ===

📊 System Metrics:
  Total Users: 101
  Online Users: 97
  Total Subreddits (Actors): 20
  Total Messages: [count]

⚡ Performance Metrics:
  Total Operations: 5000
  Elapsed Time: [time] ms
  Operations/second: [ops/sec]

🚀 Distributed System Efficiency:
  Concurrent Actors: 21 (1 Registry + 20 Subreddits)
  Average ops/actor/sec: [calculated]

=== Simulation Complete ===
```

## Requirements Met

✅ **Register account** - User registration with karma  
✅ **Create & join sub-reddit** - Dynamic subreddit creation  
✅ **Post in sub-reddit** - Text post creation  
✅ **Comment in sub-reddit** - Hierarchical comments  
✅ **Upvote+downvote + karma** - Vote system with karma calculation  
✅ **Get feed of posts** - Personalized feed  
✅ **Direct messaging** - Send and reply to messages  
✅ **Tester/simulator** - Realistic client simulator  
✅ **Zipf distribution** - True Zipf implementation  
✅ **Online/offline** - Disconnect/reconnect simulation  

## Technologies

- **Gleam v1.0+** - Type-safe functional language
- **Erlang/OTP** - Actor model runtime with supervision trees
- **BEAM VM** - Concurrent execution with millions of lightweight processes

## Detailed Documentation

See **`REPORT.md`** for comprehensive technical documentation including:
- Detailed architecture explanation
- Message flow diagrams
- Performance analysis
- Design decisions and rationale
