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

## 架构 (Architecture)

### 分布式多Actor设计

**核心理念**：实现一个"单一引擎服务" (Single-Engine Service)，对外提供统一接口，内部通过多个独立Actor实现真正的分布式处理。

#### 组件：
- **Registry Actor** (`registry.gleam`) 
  - 统一服务入口 (Facade Pattern)
  - 管理用户注册和全局路由
  - 动态创建 Subreddit Actors
  
- **Subreddit Actors** (`subreddit_actor.gleam`)
  - 每个 Subreddit 一个独立 Actor
  - 完全隔离，无共享状态
  - 并行处理帖子/评论/投票
  
- **Client Actors** (`simulator.gleam`)
  - 100 个并发客户端
  - 模拟真实用户行为
  - Zipf 分布 + 断线重连 + 转发

- **Types** (`types.gleam`)
  - 消息类型定义
  - 不可变数据结构

**关键优势**：Registry 只负责路由，不处理内容逻辑 → 避免单点瓶颈

## 文件结构

- `src/types.gleam` - 核心数据类型和消息定义
- `src/registry.gleam` - Registry Actor（统一入口）
- `src/subreddit_actor.gleam` - Subreddit Actor（独立引擎）
- `src/simulator.gleam` - 客户端模拟器（Zipf分布，真实行为）
- `src/dosp_project_4_part1.gleam` - 主入口
- `REPORT.md` - 详细技术报告

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
