// Client Simulator
import engine.{
  type EngineMessage, CreatePost, CreateSubreddit, GetFeed, JoinSubreddit,
  RegisterUser, SetUserOnline, VotePost,
}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import types.{type UserId}

// Client actor messages
pub type ClientMessage {
  PerformAction
  GoOffline
  GoOnline
  Shutdown
  UpdateFeed(posts: List(String))
  // Update known posts from feed
  AddHotPost(title: String, content: String, subreddit: String)
  // Add a hot post for potential reposting
}

// Client state
pub type ClientState {
  ClientState(
    user_id: UserId,
    username: String,
    engine: Subject(EngineMessage),
    action_count: Int,
    is_online: Bool,
    known_posts: List(String),
    // Track posts from feed for realistic voting
    hot_posts: List(HotPost),
    // Track hot posts for re-posting
  )
}

// Hot post for re-posting
pub type HotPost {
  HotPost(title: String, content: String, subreddit: String)
}

// Simulation configuration
pub type SimulationConfig {
  SimulationConfig(
    num_clients: Int,
    num_subreddits: Int,
    num_posts_per_user: Int,
    zipf_param: Float,
    simulation_duration_ms: Int,
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

// Client actor handler
fn handle_client_message(
  state: ClientState,
  message: ClientMessage,
) -> actor.Next(ClientState, ClientMessage) {
  case message {
    PerformAction -> {
      case state.is_online {
        True -> {
          // Perform a random action
          let action = int.random(100)

          case action {
            // 25% - Create/join subreddit
            n if n < 25 -> {
              let subreddit_name = "sub_" <> string.inspect(int.random(50))
              process.send(
                state.engine,
                JoinSubreddit(
                  user_id: state.user_id,
                  subreddit: subreddit_name,
                  reply: process.new_subject(),
                ),
              )
            }
            // 35% - Create post or re-post
            n if n < 60 -> {
              let subreddit_name = "sub_" <> string.inspect(int.random(50))

              // 15% chance to repost if we have hot posts
              let is_repost =
                int.random(100) < 15 && list.length(state.hot_posts) > 0

              case is_repost {
                True -> {
                  // Re-post from hot posts
                  case
                    list.drop(state.hot_posts, int.random(list.length(
                      state.hot_posts,
                    )))
                    |> list.first
                  {
                    Ok(hot_post) -> {
                      process.send(
                        state.engine,
                        CreatePost(
                          author: state.user_id,
                          subreddit: hot_post.subreddit,
                          title: "Re: " <> hot_post.title,
                          content: hot_post.content,
                          reply: process.new_subject(),
                        ),
                      )
                    }
                    Error(_) -> {
                      // Fallback to new post
                      process.send(
                        state.engine,
                        CreatePost(
                          author: state.user_id,
                          subreddit: subreddit_name,
                          title: "Post " <> string.inspect(state.action_count),
                          content: "Content from " <> state.username,
                          reply: process.new_subject(),
                        ),
                      )
                    }
                  }
                }
                False -> {
                  // Create new post
                  let post_reply = process.new_subject()
                  process.send(
                    state.engine,
                    CreatePost(
                      author: state.user_id,
                      subreddit: subreddit_name,
                      title: "Post " <> string.inspect(state.action_count),
                      content: "Content from " <> state.username,
                      reply: post_reply,
                    ),
                  )

                  // Try to add this to hot posts (20% chance for popular users)
                  case int.random(100) < 20 {
                    True -> {
                      let hot_post =
                        HotPost(
                          title: "Post " <> string.inspect(state.action_count),
                          content: "Content from " <> state.username,
                          subreddit: subreddit_name,
                        )
                      let new_hot_posts = [hot_post, ..state.hot_posts]
                      // Keep only latest 20 hot posts
                      let limited_hot_posts = case list.length(new_hot_posts) {
                        n if n > 20 -> list.take(new_hot_posts, 20)
                        _ -> new_hot_posts
                      }
                      actor.continue(ClientState(
                        ..state,
                        action_count: state.action_count + 1,
                        hot_posts: limited_hot_posts,
                      ))
                    }
                    False -> {
                      actor.continue(ClientState(
                        ..state,
                        action_count: state.action_count + 1,
                      ))
                    }
                  }
                }
              }
            }
            // 20% - Vote on post (use real post from feed)
            n if n < 80 -> {
              case list.length(state.known_posts) {
                0 -> {
                  // No known posts, get feed first
                  process.send(
                    state.engine,
                    GetFeed(user_id: state.user_id, reply: process.new_subject()),
                  )
                }
                n -> {
                  // Vote on a known post
                  case
                    list.drop(state.known_posts, int.random(n)) |> list.first
                  {
                    Ok(post_id) -> {
                      process.send(
                        state.engine,
                        VotePost(
                          post_id: post_id,
                          user_id: state.user_id,
                          is_upvote: int.random(2) == 1,
                          reply: process.new_subject(),
                        ),
                      )
                    }
                    Error(_) -> Nil
                  }
                }
              }
            }
            // 20% - Get feed to update known posts
            _ -> {
              process.send(
                state.engine,
                GetFeed(user_id: state.user_id, reply: process.new_subject()),
              )
            }
          }

          let new_state =
            ClientState(..state, action_count: state.action_count + 1)
          actor.continue(new_state)
        }
        False -> actor.continue(state)
      }
    }

    UpdateFeed(posts) -> {
      // Update known posts for realistic voting
      actor.continue(ClientState(..state, known_posts: posts))
    }

    AddHotPost(title, content, subreddit) -> {
      let hot_post = HotPost(title: title, content: content, subreddit: subreddit)
      let new_hot_posts = [hot_post, ..state.hot_posts]
      // Keep only latest 20 hot posts
      let limited_hot_posts = case list.length(new_hot_posts) {
        n if n > 20 -> list.take(new_hot_posts, 20)
        _ -> new_hot_posts
      }
      actor.continue(ClientState(..state, hot_posts: limited_hot_posts))
    }

    GoOffline -> {
      process.send(
        state.engine,
        SetUserOnline(
          user_id: state.user_id,
          is_online: False,
          reply: process.new_subject(),
        ),
      )
      let new_state = ClientState(..state, is_online: False)
      actor.continue(new_state)
    }

    GoOnline -> {
      process.send(
        state.engine,
        SetUserOnline(
          user_id: state.user_id,
          is_online: True,
          reply: process.new_subject(),
        ),
      )
      let new_state = ClientState(..state, is_online: True)
      actor.continue(new_state)
    }

    Shutdown -> actor.stop()
  }
}

// Start a client actor
pub fn start_client(
  username: String,
  user_id: UserId,
  engine: Subject(EngineMessage),
) -> Result(actor.Started(Subject(ClientMessage)), actor.StartError) {
  let state =
    ClientState(
      user_id: user_id,
      username: username,
      engine: engine,
      action_count: 0,
      is_online: True,
      known_posts: [],
      hot_posts: [],
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

// Run simulation coordinator
pub fn run_simulation(
  config: SimulationConfig,
  engine: Subject(EngineMessage),
) -> SimulationStats {
  io.println("=== Starting Reddit Clone Simulation ===")
  io.println("Clients: " <> string.inspect(config.num_clients))
  io.println("Subreddits: " <> string.inspect(config.num_subreddits))
  io.println(
    "Duration: " <> string.inspect(config.simulation_duration_ms) <> " ms",
  )
  io.println("")

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
          process.send(engine, RegisterUser(username: "system", reply: reply))
          let _result = process.receive(reply, 1000)
          Nil
        }
        _ -> Nil
      }

      let reply = process.new_subject()
      process.send(
        engine,
        CreateSubreddit(name: subreddit_name, creator: creator_id, reply: reply),
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
        engine,
        RegisterUser(username: username, reply: register_reply),
      )

      case process.receive(register_reply, 1000) {
        Ok(result) -> {
          case result {
            Ok(user_id) -> {
              // Start client actor
              case start_client(username, user_id, engine) {
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
                        let join_reply = process.new_subject()
                        process.send(
                          engine,
                          JoinSubreddit(
                            user_id: user_id,
                            subreddit: sub_name,
                            reply: join_reply,
                          ),
                        )
                        let _result = process.receive(join_reply, 1000)
                        Nil
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

  // Run simulation - send actions to clients
  io.println("Running simulation...")
  let num_actions = config.num_clients * config.num_posts_per_user

  list.range(1, num_actions)
  |> list.each(fn(i) {
    // Pick a random client
    case list.length(clients) {
      0 -> Nil
      n -> {
        let client_idx = int.random(n)
        case list.drop(clients, client_idx) |> list.first {
          Ok(client) -> {
            process.send(client, PerformAction)
          }
          Error(_) -> Nil
        }

        // Simulate disconnection/reconnection every 100 actions
        // About 5% of users go offline, then come back online
        case i % 100 {
          0 -> {
            let num_to_disconnect = n / 20
            // 5% of clients

            // Disconnect some clients
            list.range(1, num_to_disconnect)
            |> list.each(fn(_) {
              let disconnect_idx = int.random(n)
              case list.drop(clients, disconnect_idx) |> list.first {
                Ok(client) -> process.send(client, GoOffline)
                Error(_) -> Nil
              }
            })
          }
          50 -> {
            // Reconnect them halfway through the cycle
            let num_to_reconnect = n / 20

            list.range(1, num_to_reconnect)
            |> list.each(fn(_) {
              let reconnect_idx = int.random(n)
              case list.drop(clients, reconnect_idx) |> list.first {
                Ok(client) -> process.send(client, GoOnline)
                Error(_) -> Nil
              }
            })
          }
          _ -> Nil
        }

        // Small delay to simulate real usage
        process.sleep(5)
      }
    }
  })

  io.println("")
  io.println("Simulation complete!")
  io.println("")

  // Get final stats from engine
  let stats_reply = process.new_subject()
  process.send(engine, engine.GetStats(reply: stats_reply))

  case process.receive(stats_reply, 1000) {
    Ok(engine_stats) -> {
      io.println("=== Final Statistics ===")
      io.println("Total Users: " <> string.inspect(engine_stats.total_users))
      io.println("Online Users: " <> string.inspect(engine_stats.online_users))
      io.println(
        "Total Subreddits: " <> string.inspect(engine_stats.total_subreddits),
      )
      io.println("Total Posts: " <> string.inspect(engine_stats.total_posts))
      io.println(
        "Total Comments: " <> string.inspect(engine_stats.total_comments),
      )
      io.println(
        "Total Messages: " <> string.inspect(engine_stats.total_messages),
      )

      let actions_per_sec = case config.simulation_duration_ms {
        0 -> 0.0
        ms -> int.to_float(num_actions) /. int.to_float(ms) *. 1000.0
      }

      io.println("Actions/second: " <> string.inspect(actions_per_sec))
    }
    Error(_) -> {
      io.println("Failed to get engine statistics")
    }
  }

  // Shutdown clients
  list.each(clients, fn(client) { process.send(client, Shutdown) })

  SimulationStats(
    total_clients: list.length(clients),
    total_actions: num_actions,
    total_subreddits_created: config.num_subreddits,
    total_posts_created: 0,
    total_comments_created: 0,
    elapsed_time_ms: config.simulation_duration_ms,
    actions_per_second: 0.0,
  )
}
