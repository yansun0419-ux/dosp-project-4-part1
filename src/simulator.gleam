// Client Simulator - Distributed Version
@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: Int) -> Int

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import types.{
  type Post, type RegistryMessage, type SubredditMessage, type SubredditName,
  type UserId,
}

// Client actor messages
pub type ClientMessage {
  PerformAction
  GoOffline
  GoOnline
  Shutdown
  UpdateFeed(posts: List(String))
  AddHotPost(title: String, content: String, subreddit: String)
  GetStats(reply: Subject(ClientStats))
}

// Client statistics
pub type ClientStats {
  ClientStats(user_id: UserId, actions_completed: Int, is_online: Bool)
}

// Client state - Distributed version
pub type ClientState {
  ClientState(
    user_id: UserId,
    username: String,
    registry: Subject(RegistryMessage),
    action_count: Int,
    is_online: Bool,
    known_posts: List(String),
    hot_posts: List(HotPost),
    subreddit_cache: Dict(SubredditName, Subject(SubredditMessage)),
    available_subreddits: List(SubredditName),
    zipf_param: Float,
  )
}

// Hot post for re-posting
pub type HotPost {
  HotPost(title: String, content: String, subreddit: String)
}

// Helper function: Get Subreddit Actor address (with caching)
fn get_subreddit_actor(
  state: ClientState,
  subreddit_name: SubredditName,
) -> Result(#(Subject(SubredditMessage), ClientState), Nil) {
  // Check cache first
  case dict.get(state.subreddit_cache, subreddit_name) {
    Ok(actor_subject) -> Ok(#(actor_subject, state))
    Error(_) -> {
      // Cache miss, query registry
      let reply = process.new_subject()
      process.send(
        state.registry,
        types.GetSubredditActor(name: subreddit_name, reply: reply),
      )

      case process.receive(reply, 1000) {
        Ok(Ok(actor_subject)) -> {
          // Successfully obtained, add to cache
          let new_cache =
            dict.insert(state.subreddit_cache, subreddit_name, actor_subject)
          let new_state = ClientState(..state, subreddit_cache: new_cache)
          Ok(#(actor_subject, new_state))
        }
        _ -> Error(Nil)
      }
    }
  }
}

// Simulation configuration
pub type SimulationConfig {
  SimulationConfig(
    num_clients: Int,
    num_subreddits: Int,
    num_posts_per_user: Int,
    zipf_param: Float,
    simulation_duration_ms: Int,
    progress_update_interval: Int,
  )
}

// Generate Zipf distribution rank for subreddit popularity
pub fn zipf_rank(rank: Int, s: Float, n: Int) -> Float {
  let rank_float = int.to_float(rank)
  let s_power = float.power(rank_float, s)

  case s_power {
    Ok(power) -> {
      // Calculate harmonic number H(n,s)
      let h_n_s = harmonic_number(n, s)
      case h_n_s {
        Ok(harmonic) -> 1.0 /. power /. harmonic
        Error(_) -> 0.0
      }
    }
    Error(_) -> 0.0
  }
}

fn harmonic_number(n: Int, s: Float) -> Result(Float, Nil) {
  list.range(1, n)
  |> list.map(fn(i) {
    let i_float = int.to_float(i)
    case float.power(i_float, s) {
      Ok(power) -> 1.0 /. power
      Error(_) -> 0.0
    }
  })
  |> list.fold(0.0, fn(acc, val) { acc +. val })
  |> Ok
}

// Select a random element from list weighted by Zipf distribution
pub fn select_by_zipf(items: List(a), zipf_s: Float) -> Result(a, Nil) {
  let n = list.length(items)
  case n {
    0 -> Error(Nil)
    _ -> {
      // Calculate cumulative probabilities for each rank
      let probabilities =
        list.range(1, n)
        |> list.map(fn(rank) { zipf_rank(rank, zipf_s, n) })

      // Calculate cumulative sum
      let cumulative =
        probabilities
        |> list.scan(0.0, fn(acc, p) { acc +. p })

      // Generate random number between 0 and 1
      let random_val = int.to_float(int.random(10_000)) /. 10_000.0

      // Find the rank that corresponds to this random value
      let selected_rank =
        cumulative
        |> list.index_fold(1, fn(selected, cum_prob, idx) {
          case random_val <. cum_prob, selected == 1 {
            True, True -> idx + 1
            _, _ -> selected
          }
        })

      // Return the item at the selected rank
      list.drop(items, selected_rank - 1)
      |> list.first
    }
  }
}

// Client actor handler - Distributed version
fn handle_client_message(
  state: ClientState,
  message: ClientMessage,
) -> actor.Next(ClientState, ClientMessage) {
  case message {
    PerformAction -> {
      case state.is_online {
        True -> {
          // Increment action count (we're processing this action)
          let state = ClientState(..state, action_count: state.action_count + 1)

          // Perform a random action
          let action = int.random(100)

          case action {
            // 25% - Create/join subreddit
            n if n < 25 -> {
              let subreddit_name = "sub_" <> string.inspect(int.random(50))

              // Distributed approach: Get subreddit actor first
              case get_subreddit_actor(state, subreddit_name) {
                Ok(#(subreddit_actor, new_state)) -> {
                  let join_reply = process.new_subject()
                  process.send(
                    subreddit_actor,
                    types.JoinSubreddit(
                      user_id: state.user_id,
                      reply: join_reply,
                    ),
                  )
                  // Wait for join confirmation
                  let _result = process.receive(join_reply, 100)
                  actor.continue(new_state)
                }
                Error(_) -> {
                  // Subreddit doesn't exist, create it first
                  let reply = process.new_subject()
                  process.send(
                    state.registry,
                    types.CreateSubreddit(
                      name: subreddit_name,
                      creator: state.user_id,
                      registry_subject: state.registry,
                      reply: reply,
                    ),
                  )
                  // Wait for creation result, then add to cache
                  case process.receive(reply, 1000) {
                    Ok(Ok(subreddit_actor)) -> {
                      let new_cache =
                        dict.insert(
                          state.subreddit_cache,
                          subreddit_name,
                          subreddit_actor,
                        )
                      let new_state =
                        ClientState(..state, subreddit_cache: new_cache)

                      // Join this newly created subreddit
                      let join_reply = process.new_subject()
                      process.send(
                        subreddit_actor,
                        types.JoinSubreddit(
                          user_id: state.user_id,
                          reply: join_reply,
                        ),
                      )
                      // Wait for join confirmation
                      let _result = process.receive(join_reply, 100)
                      actor.continue(new_state)
                    }
                    _ -> actor.continue(state)
                  }
                }
              }
            }
            // 35% - Create post or re-post
            n if n < 60 -> {
              // Use Zipf distribution to select subreddit (popular subs get more posts)
              let subreddit_name = case
                select_by_zipf(state.available_subreddits, state.zipf_param)
              {
                Ok(name) -> name
                Error(_) -> "sub_1"
              }

              // 15% chance to repost if we have hot posts
              let is_repost = int.random(100) < 15 && state.hot_posts != []

              let #(title, content) = case is_repost {
                True -> {
                  case
                    list.drop(
                      state.hot_posts,
                      int.random(list.length(state.hot_posts)),
                    )
                    |> list.first
                  {
                    Ok(hot_post) -> #(
                      "Re: " <> hot_post.title,
                      hot_post.content,
                    )
                    Error(_) -> #(
                      "Post " <> string.inspect(state.action_count),
                      "Content from " <> state.username,
                    )
                  }
                }
                False -> #(
                  "Post " <> string.inspect(state.action_count),
                  "Content from " <> state.username,
                )
              }

              // Distributed approach: Get subreddit actor then create post
              case get_subreddit_actor(state, subreddit_name) {
                Ok(#(subreddit_actor, new_state)) -> {
                  let post_reply = process.new_subject()
                  process.send(
                    subreddit_actor,
                    types.CreatePost(
                      author: state.user_id,
                      title: title,
                      content: content,
                      reply: post_reply,
                    ),
                  )

                  // Wait for post creation confirmation
                  let _post_result = process.receive(post_reply, 100)

                  // 20% chance to add to hot posts pool
                  case int.random(100) < 20, is_repost {
                    True, False -> {
                      let hot_post =
                        HotPost(
                          title: title,
                          content: content,
                          subreddit: subreddit_name,
                        )
                      let new_hot_posts = [hot_post, ..new_state.hot_posts]
                      let limited_hot_posts = case list.length(new_hot_posts) {
                        n if n > 20 -> list.take(new_hot_posts, 20)
                        _ -> new_hot_posts
                      }
                      actor.continue(
                        ClientState(..new_state, hot_posts: limited_hot_posts),
                      )
                    }
                    _, _ -> actor.continue(new_state)
                  }
                }
                Error(_) -> {
                  // Subreddit doesn't exist, skip for now
                  actor.continue(state)
                }
              }
            }
            // 15% - Create comment on a post
            n if n < 75 -> {
              case list.length(state.known_posts) {
                0 -> {
                  // No known posts, skip for now
                  actor.continue(state)
                }
                n -> {
                  // Comment on a known post
                  case
                    list.drop(state.known_posts, int.random(n)) |> list.first
                  {
                    Ok(post_id) -> {
                      // Extract subreddit name from post_id
                      // Post ID format: "subreddit_name_post_123"
                      // We need to extract "subreddit_name" part
                      let subreddit_name = case
                        string.split(post_id, "_post_")
                      {
                        [sub_name, ..] -> sub_name
                        _ -> "sub_1"
                        // fallback
                      }

                      case get_subreddit_actor(state, subreddit_name) {
                        Ok(#(subreddit_actor, new_state)) -> {
                          let comment_content =
                            "Comment from "
                            <> state.username
                            <> " on action "
                            <> string.inspect(state.action_count)

                          let comment_reply = process.new_subject()
                          process.send(
                            subreddit_actor,
                            types.CreateComment(
                              author: state.user_id,
                              post_id: post_id,
                              parent_comment_id: None,
                              content: comment_content,
                              reply: comment_reply,
                            ),
                          )
                          // Wait for comment creation confirmation
                          let _comment_result =
                            process.receive(comment_reply, 100)
                          actor.continue(new_state)
                        }
                        Error(_) -> actor.continue(state)
                      }
                    }
                    Error(_) -> actor.continue(state)
                  }
                }
              }
            }
            // 10% - Vote on post
            n if n < 85 -> {
              case list.length(state.known_posts) {
                0 -> {
                  // No known posts, skip for now
                  actor.continue(state)
                }
                n -> {
                  // Vote on known post
                  case
                    list.drop(state.known_posts, int.random(n)) |> list.first
                  {
                    Ok(post_id) -> {
                      // Extract subreddit name from post_id
                      // Post ID format: "subreddit_name_post_123"
                      let subreddit_name = case
                        string.split(post_id, "_post_")
                      {
                        [sub_name, ..] -> sub_name
                        _ -> "sub_1"
                        // fallback
                      }

                      case get_subreddit_actor(state, subreddit_name) {
                        Ok(#(subreddit_actor, new_state)) -> {
                          let vote_reply = process.new_subject()
                          process.send(
                            subreddit_actor,
                            types.VotePost(
                              post_id: post_id,
                              user_id: state.user_id,
                              is_upvote: int.random(2) == 1,
                              reply: vote_reply,
                            ),
                          )
                          // Wait for vote confirmation (short timeout)
                          let _vote_result = process.receive(vote_reply, 50)
                          actor.continue(new_state)
                        }
                        Error(_) -> actor.continue(state)
                      }
                    }
                    Error(_) -> actor.continue(state)
                  }
                }
              }
            }
            // 15% - Get feed to update known posts
            _ -> {
              // Use Zipf to select subreddit
              let subreddit_name = case
                select_by_zipf(state.available_subreddits, state.zipf_param)
              {
                Ok(name) -> name
                Error(_) -> "sub_1"
              }

              case get_subreddit_actor(state, subreddit_name) {
                Ok(#(subreddit_actor, new_state)) -> {
                  let feed_reply = process.new_subject()
                  process.send(
                    subreddit_actor,
                    types.GetFeed(user_id: state.user_id, reply: feed_reply),
                  )

                  // Try to receive feed and update known_posts
                  case process.receive(feed_reply, 500) {
                    Ok(Ok(posts)) -> {
                      // Store hot posts for potential re-posting
                      let post_ids = list.map(posts, fn(post: Post) { post.id })
                      actor.continue(
                        ClientState(..new_state, known_posts: post_ids),
                      )
                    }
                    _ -> actor.continue(new_state)
                  }
                }
                Error(_) -> actor.continue(state)
              }
            }
          }
        }
        False -> actor.continue(state)
      }
    }

    UpdateFeed(posts) -> {
      // Update known posts for realistic voting
      actor.continue(ClientState(..state, known_posts: posts))
    }

    AddHotPost(title, content, subreddit) -> {
      let hot_post =
        HotPost(title: title, content: content, subreddit: subreddit)
      let new_hot_posts = [hot_post, ..state.hot_posts]
      // Keep only latest 20 hot posts
      let limited_hot_posts = case list.length(new_hot_posts) {
        n if n > 20 -> list.take(new_hot_posts, 20)
        _ -> new_hot_posts
      }
      actor.continue(ClientState(..state, hot_posts: limited_hot_posts))
    }

    GoOffline -> {
      let status_reply = process.new_subject()
      process.send(
        state.registry,
        types.SetUserOnline(
          user_id: state.user_id,
          is_online: False,
          reply: status_reply,
        ),
      )
      // Wait for status update confirmation
      let _status_result = process.receive(status_reply, 100)
      let new_state = ClientState(..state, is_online: False)
      actor.continue(new_state)
    }

    GoOnline -> {
      let status_reply = process.new_subject()
      process.send(
        state.registry,
        types.SetUserOnline(
          user_id: state.user_id,
          is_online: True,
          reply: status_reply,
        ),
      )
      // Wait for status update confirmation
      let _status_result = process.receive(status_reply, 100)
      let new_state = ClientState(..state, is_online: True)
      actor.continue(new_state)
    }

    GetStats(reply) -> {
      let stats =
        ClientStats(
          user_id: state.user_id,
          actions_completed: state.action_count,
          is_online: state.is_online,
        )
      process.send(reply, stats)
      actor.continue(state)
    }

    Shutdown -> actor.stop()
  }
}

// Start a client actor - Distributed version
pub fn start_client(
  username: String,
  user_id: UserId,
  registry: Subject(RegistryMessage),
  available_subreddits: List(SubredditName),
  zipf_param: Float,
) -> Result(actor.Started(Subject(ClientMessage)), actor.StartError) {
  let state =
    ClientState(
      user_id: user_id,
      username: username,
      registry: registry,
      action_count: 0,
      is_online: True,
      known_posts: [],
      hot_posts: [],
      subreddit_cache: dict.new(),
      available_subreddits: available_subreddits,
      zipf_param: zipf_param,
    )

  actor.new(state)
  |> actor.on_message(handle_client_message)
  |> actor.start
}

// Simulation statistics
pub type SimulationStats {
  SimulationStats(
    total_clients: Int,
    total_actions: Int,
    total_subreddits_created: Int,
    total_posts_created: Int,
    total_comments_created: Int,
    elapsed_time_ms: Int,
    actions_per_second: Float,
  )
}

// Run simulation coordinator - Distributed version
pub fn run_simulation(
  config: SimulationConfig,
  registry: Subject(RegistryMessage),
) -> SimulationStats {
  io.println("=== Starting Reddit Clone Simulation ===")
  io.println("Clients: " <> string.inspect(config.num_clients))
  io.println("Subreddits: " <> string.inspect(config.num_subreddits))
  io.println(
    "Target Operations: "
    <> string.inspect(config.num_clients * config.num_posts_per_user),
  )
  io.println("")

  // Record start time for performance measurement (microseconds)
  // 1000000 = microsecond in Erlang time units
  let start_time = monotonic_time(1_000_000)

  // Create subreddits with Zipf distribution
  io.println("Creating subreddits...")
  let subreddits =
    list.range(1, config.num_subreddits)
    |> list.map(fn(i) {
      let subreddit_name = "sub_" <> string.inspect(i)
      let creator_id = "user_system"

      // Register system user if needed
      case i {
        1 -> {
          let reply = process.new_subject()
          process.send(
            registry,
            types.RegisterUser(username: "system", reply: reply),
          )
          let _result = process.receive(reply, 1000)
          Nil
        }
        _ -> Nil
      }

      let reply = process.new_subject()
      process.send(
        registry,
        types.CreateSubreddit(
          name: subreddit_name,
          creator: creator_id,
          registry_subject: registry,
          reply: reply,
        ),
      )
      let _result = process.receive(reply, 1000)

      subreddit_name
    })

  io.println(
    "Created " <> string.inspect(list.length(subreddits)) <> " subreddits",
  )
  io.println("")

  // Register users and create clients
  io.println("Registering users and starting clients...")
  let clients =
    list.range(1, config.num_clients)
    |> list.map(fn(i) {
      let username = "user" <> string.inspect(i)

      // Register user
      let register_reply = process.new_subject()
      process.send(
        registry,
        types.RegisterUser(username: username, reply: register_reply),
      )

      case process.receive(register_reply, 1000) {
        Ok(result) -> {
          case result {
            Ok(user_id) -> {
              // Start client actor
              case
                start_client(
                  username,
                  user_id,
                  registry,
                  subreddits,
                  config.zipf_param,
                )
              {
                Ok(started) -> {
                  // Join some subreddits based on Zipf distribution
                  let num_subs_to_join = case i {
                    n if n <= 10 -> 10
                    // Top users join many subs
                    n if n <= 50 -> 5
                    n if n <= 200 -> 2
                    _ -> 1
                  }

                  list.range(1, num_subs_to_join)
                  |> list.each(fn(_) {
                    case select_by_zipf(subreddits, config.zipf_param) {
                      Ok(sub_name) -> {
                        // Get subreddit actor
                        let get_actor_reply = process.new_subject()
                        process.send(
                          registry,
                          types.GetSubredditActor(
                            name: sub_name,
                            reply: get_actor_reply,
                          ),
                        )

                        case process.receive(get_actor_reply, 1000) {
                          Ok(Ok(subreddit_actor)) -> {
                            let join_reply = process.new_subject()
                            process.send(
                              subreddit_actor,
                              types.JoinSubreddit(
                                user_id: user_id,
                                reply: join_reply,
                              ),
                            )
                            let _result = process.receive(join_reply, 1000)
                            Nil
                          }
                          _ -> Nil
                        }
                      }
                      Error(_) -> Nil
                    }
                  })

                  Some(started.data)
                }
                Error(_) -> None
              }
            }
            Error(_) -> None
          }
        }
        Error(_) -> None
      }
    })
    |> list.filter_map(fn(opt) {
      case opt {
        Some(client) -> Ok(client)
        None -> Error(Nil)
      }
    })

  io.println(
    "Started " <> string.inspect(list.length(clients)) <> " client actors",
  )
  io.println("")

  // Run simulation - send ALL actions to clients concurrently
  // Each client actor will process its actions independently
  io.println("Running distributed simulation...")
  io.println(
    "Sending "
    <> string.inspect(config.num_posts_per_user)
    <> " actions to each of "
    <> string.inspect(list.length(clients))
    <> " clients...",
  )

  // Send all actions to all clients - they'll run in parallel!
  clients
  |> list.each(fn(client) {
    list.range(1, config.num_posts_per_user)
    |> list.each(fn(_) { process.send(client, PerformAction) })
  })

  // Simulate disconnection/reconnection
  let num_clients = list.length(clients)
  case num_clients {
    0 -> Nil
    n -> {
      // Disconnect 5% of clients
      let num_to_disconnect = n / 20
      list.range(1, num_to_disconnect)
      |> list.each(fn(_) {
        let disconnect_idx = int.random(n)
        case list.drop(clients, disconnect_idx) |> list.first {
          Ok(client) -> process.send(client, GoOffline)
          Error(_) -> Nil
        }
      })

      // Wait a bit
      process.sleep(500)

      // Reconnect them
      list.range(1, num_to_disconnect)
      |> list.each(fn(_) {
        let reconnect_idx = int.random(n)
        case list.drop(clients, reconnect_idx) |> list.first {
          Ok(client) -> process.send(client, GoOnline)
          Error(_) -> Nil
        }
      })
    }
  }

  // Give actors time to process (they're running concurrently!)
  io.println("Processing actions across distributed actors...")
  io.println(
    "(Waiting "
    <> string.inspect(config.simulation_duration_ms / 1000)
    <> " seconds for processing...)",
  )

  process.sleep(config.simulation_duration_ms)

  io.println("")
  io.println("Simulation complete!")
  io.println("")

  // Calculate elapsed time (in microseconds, convert to milliseconds)
  let end_time = monotonic_time(1_000_000)
  let elapsed_microseconds = end_time - start_time
  let elapsed_ms = elapsed_microseconds / 1000

  // Query all client actors to get actual completed actions
  io.println("Collecting action counts from all client actors...")

  let client_stats_list =
    clients
    |> list.filter_map(fn(client) {
      let stats_reply = process.new_subject()
      process.send(client, GetStats(reply: stats_reply))

      case process.receive(stats_reply, 1000) {
        Ok(stats) -> Ok(stats)
        Error(_) -> Error(Nil)
      }
    })

  // Calculate total completed actions
  let actual_operations =
    client_stats_list
    |> list.fold(0, fn(acc, stats) { acc + stats.actions_completed })

  let target_operations = config.num_clients * config.num_posts_per_user

  // Also get subreddit stats for posts/comments breakdown
  let subreddit_stats_list =
    subreddits
    |> list.filter_map(fn(sub_name) {
      let get_actor_reply = process.new_subject()
      process.send(
        registry,
        types.GetSubredditActor(name: sub_name, reply: get_actor_reply),
      )

      case process.receive(get_actor_reply, 1000) {
        Ok(Ok(subreddit_actor)) -> {
          let stats_reply = process.new_subject()
          process.send(
            subreddit_actor,
            types.GetSubredditStats(reply: stats_reply),
          )

          case process.receive(stats_reply, 1000) {
            Ok(stats) -> Ok(stats)
            Error(_) -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })

  let actual_posts =
    subreddit_stats_list
    |> list.fold(0, fn(acc, stats) { acc + stats.total_posts })

  let actual_comments =
    subreddit_stats_list
    |> list.fold(0, fn(acc, stats) { acc + stats.total_comments })

  // Get final statistics from registry
  let stats_reply = process.new_subject()
  process.send(registry, types.GetRegistryStats(reply: stats_reply))

  case process.receive(stats_reply, 1000) {
    Ok(registry_stats) -> {
      io.println("=== Performance Statistics ===")
      io.println("")
      io.println("System Metrics:")
      io.println(
        "  Total Users: " <> string.inspect(registry_stats.total_users),
      )
      io.println(
        "  Online Users: " <> string.inspect(registry_stats.online_users),
      )
      io.println(
        "  Total Subreddits (Actors): "
        <> string.inspect(registry_stats.total_subreddits),
      )
      io.println(
        "  Total Messages: " <> string.inspect(registry_stats.total_messages),
      )
      io.println("")

      io.println("Performance Metrics:")
      io.println(
        "  Target Operations Sent: " <> string.inspect(target_operations),
      )
      io.println(
        "  Actual Operations Completed: " <> string.inspect(actual_operations),
      )
      io.println("    - Posts Created: " <> string.inspect(actual_posts))
      io.println("    - Comments Created: " <> string.inspect(actual_comments))
      io.println(
        "  Completion Rate: "
        <> float.to_string(
          int.to_float(actual_operations)
          /. int.to_float(target_operations)
          *. 100.0,
        )
        <> "%",
      )
      io.println("  Elapsed Time: " <> string.inspect(elapsed_ms) <> " ms")

      let actual_duration = case elapsed_ms {
        0 -> 1
        n -> n
      }

      let ops_per_second =
        int.to_float(actual_operations)
        /. int.to_float(actual_duration)
        *. 1000.0
      let ops_per_minute = ops_per_second *. 60.0

      io.println(
        "  Operations/second (actual): " <> float.to_string(ops_per_second),
      )
      io.println(
        "  Operations/minute (actual): " <> float.to_string(ops_per_minute),
      )

      // Calculate theoretical maximum
      // Removed unused theoretical_max calculation
      io.println("")
      io.println("Distributed System Efficiency:")
      io.println(
        "  Concurrent Actors: "
        <> string.inspect(registry_stats.total_subreddits + 1),
      )
      io.println(
        "  Average ops/actor/sec: "
        <> float.to_string(
          ops_per_second /. int.to_float(registry_stats.total_subreddits + 1),
        ),
      )
    }
    Error(_) -> {
      io.println("Failed to get engine statistics")
    }
  }

  // Shutdown all clients
  list.each(clients, fn(client) { process.send(client, Shutdown) })

  let ops_per_second = case elapsed_ms {
    0 -> 0.0
    _ -> int.to_float(actual_operations) /. int.to_float(elapsed_ms) *. 1000.0
  }

  SimulationStats(
    total_clients: list.length(clients),
    total_actions: actual_operations,
    total_subreddits_created: config.num_subreddits,
    total_posts_created: actual_posts,
    total_comments_created: actual_comments,
    elapsed_time_ms: elapsed_ms,
    actions_per_second: ops_per_second,
  )
}
