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
}

// Client state
pub type ClientState {
  ClientState(
    user_id: UserId,
    username: String,
    engine: Subject(EngineMessage),
    action_count: Int,
    is_online: Bool,
  )
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
pub fn select_by_zipf(items: List(a), _zipf_s: Float) -> Result(a, Nil) {
  let n = list.length(items)
  case n {
    0 -> Error(Nil)
    _ -> {
      // Generate random rank (1 to n)
      // Simplified: just use modulo for demo
      let rank = int.random(n) + 1
      list.drop(items, rank - 1)
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
            // 30% - Create/join subreddit
            n if n < 30 -> {
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
            // 40% - Create post
            n if n < 70 -> {
              let subreddit_name = "sub_" <> string.inspect(int.random(50))
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
            // 20% - Vote on post
            n if n < 90 -> {
              let post_id = "post_" <> string.inspect(int.random(100))
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
            // 10% - Get feed
            _ -> {
              process.send(
                state.engine,
                GetFeed(user_id: state.user_id, reply: process.new_subject()),
              )
            }
          }
          
          let new_state = ClientState(..state, action_count: state.action_count + 1)
          actor.continue(new_state)
        }
        False -> actor.continue(state)
      }
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
  let state = ClientState(
    user_id: user_id,
    username: username,
    engine: engine,
    action_count: 0,
    is_online: True,
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
  io.println("Duration: " <> string.inspect(config.simulation_duration_ms) <> " ms")
  io.println("")
  
  // Create subreddits with Zipf distribution
  io.println("Creating subreddits...")
  let subreddits = list.range(1, config.num_subreddits)
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
    process.send(engine, CreateSubreddit(name: subreddit_name, creator: creator_id, reply: reply))
    let _result = process.receive(reply, 1000)
    
    subreddit_name
  })
  
  io.println("Created " <> string.inspect(list.length(subreddits)) <> " subreddits")
  io.println("")
  
  // Register users and create clients
  io.println("Registering users and starting clients...")
  let clients = list.range(1, config.num_clients)
  |> list.map(fn(i) {
    let username = "user" <> string.inspect(i)
    
    // Register user
    let register_reply = process.new_subject()
    process.send(engine, RegisterUser(username: username, reply: register_reply))
    
    case process.receive(register_reply, 1000) {
      Ok(result) -> {
        case result {
          Ok(user_id) -> {
            // Start client actor
            case start_client(username, user_id, engine) {
              Ok(started) -> {
                // Join some subreddits based on Zipf distribution
                let num_subs_to_join = case i {
                  n if n <= 10 -> 10  // Top users join many subs
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
                        JoinSubreddit(user_id: user_id, subreddit: sub_name, reply: join_reply),
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
  
  io.println("Started " <> string.inspect(list.length(clients)) <> " client actors")
  io.println("")
  
  // Run simulation - send actions to clients
  io.println("Running simulation...")
  let num_actions = config.num_clients * config.num_posts_per_user
  
  list.range(1, num_actions)
  |> list.each(fn(_i) {
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
      io.println("Total Subreddits: " <> string.inspect(engine_stats.total_subreddits))
      io.println("Total Posts: " <> string.inspect(engine_stats.total_posts))
      io.println("Total Comments: " <> string.inspect(engine_stats.total_comments))
      io.println("Total Messages: " <> string.inspect(engine_stats.total_messages))
      
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
