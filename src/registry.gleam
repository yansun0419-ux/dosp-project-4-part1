// Registry Actor - Central Registry
// Responsibilities: User registration, Subreddit Actor creation and routing, Direct messages

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import subreddit_actor
import types.{
  type DirectMessage, type MessageId, type RegistryMessage, type RegistryState,
  type RegistryStats, type SubredditMessage, type SubredditName, type User,
  type UserId, DirectMessage, RegistryState, RegistryStats, User,
}

// Handle Registry messages
fn handle_registry_message(
  state: RegistryState,
  message: RegistryMessage,
) -> actor.Next(RegistryState, RegistryMessage) {
  case message {
    // ===== User Operations =====
    types.RegisterUser(username, reply) -> {
      // Generate new user ID
      let user_id =
        "user_" <> username <> "_" <> string.inspect(dict.size(state.users))

      case dict.get(state.users, user_id) {
        Ok(_) -> {
          // User already exists
          process.send(reply, Error("User already exists"))
          actor.continue(state)
        }
        Error(_) -> {
          // Create new user
          let new_user =
            User(
              id: user_id,
              username: username,
              karma: 0,
              subscribed_subreddits: [],
              is_online: True,
            )

          let new_users = dict.insert(state.users, user_id, new_user)
          process.send(reply, Ok(user_id))

          actor.continue(RegistryState(..state, users: new_users))
        }
      }
    }

    types.GetUser(user_id, reply) -> {
      case dict.get(state.users, user_id) {
        Ok(user) -> process.send(reply, Ok(user))
        Error(_) -> process.send(reply, Error("User not found"))
      }
      actor.continue(state)
    }

    types.SetUserOnline(user_id, is_online, reply) -> {
      case dict.get(state.users, user_id) {
        Ok(user) -> {
          let updated_user = User(..user, is_online: is_online)
          let new_users = dict.insert(state.users, user_id, updated_user)
          process.send(reply, Ok(Nil))
          actor.continue(RegistryState(..state, users: new_users))
        }
        Error(_) -> {
          process.send(reply, Error("User not found"))
          actor.continue(state)
        }
      }
    }

    types.UpdateKarma(user_id, delta) -> {
      case dict.get(state.users, user_id) {
        Ok(user) -> {
          let updated_user = User(..user, karma: user.karma + delta)
          let new_users = dict.insert(state.users, user_id, updated_user)
          actor.continue(RegistryState(..state, users: new_users))
        }
        Error(_) -> {
          // User not found, ignore
          actor.continue(state)
        }
      }
    }

    // ===== Subreddit Management =====
    types.CreateSubreddit(name, creator, registry_subject, reply) -> {
      case dict.get(state.subreddit_actors, name) {
        Ok(actor_ref) -> {
          // Subreddit already exists, return existing actor
          process.send(reply, Ok(actor_ref.subject))
          actor.continue(state)
        }
        Error(_) -> {
          // Create new Subreddit Actor
          case subreddit_actor.start(name, creator, registry_subject) {
            Ok(started) -> {
              let actor_ref =
                types.SubredditActorRef(name: name, subject: started.data)

              let new_subreddit_actors =
                dict.insert(state.subreddit_actors, name, actor_ref)

              process.send(reply, Ok(started.data))
              actor.continue(
                RegistryState(..state, subreddit_actors: new_subreddit_actors),
              )
            }
            Error(_) -> {
              process.send(reply, Error("Failed to create subreddit actor"))
              actor.continue(state)
            }
          }
        }
      }
    }

    types.GetSubredditActor(name, reply) -> {
      case dict.get(state.subreddit_actors, name) {
        Ok(actor_ref) -> process.send(reply, Ok(actor_ref.subject))
        Error(_) -> process.send(reply, Error("Subreddit not found"))
      }
      actor.continue(state)
    }

    // ===== Direct Message Operations =====
    types.SendDirectMessage(from, to, content, reply) -> {
      // Check if sender and receiver exist
      case dict.get(state.users, from), dict.get(state.users, to) {
        Ok(_), Ok(_) -> {
          let message_id = "msg_" <> string.inspect(state.next_message_id)

          let new_message =
            DirectMessage(
              id: message_id,
              from: from,
              to: to,
              content: content,
              read: False,
              created_at: 0,
            )

          let new_messages =
            dict.insert(state.messages, message_id, new_message)

          process.send(reply, Ok(message_id))
          actor.continue(
            RegistryState(
              ..state,
              messages: new_messages,
              next_message_id: state.next_message_id + 1,
            ),
          )
        }
        _, _ -> {
          process.send(reply, Error("User not found"))
          actor.continue(state)
        }
      }
    }

    types.GetDirectMessages(user_id, reply) -> {
      let user_messages =
        dict.values(state.messages)
        |> list.filter(fn(msg) { msg.to == user_id })

      process.send(reply, Ok(user_messages))
      actor.continue(state)
    }

    types.ReplyToDirectMessage(message_id, from, content, reply) -> {
      case dict.get(state.messages, message_id) {
        Ok(original_msg) -> {
          let new_msg_id = "msg_" <> string.inspect(state.next_message_id)

          let new_message =
            DirectMessage(
              id: new_msg_id,
              from: from,
              to: original_msg.from,
              content: content,
              read: False,
              created_at: 0,
            )

          let new_messages =
            dict.insert(state.messages, new_msg_id, new_message)

          process.send(reply, Ok(new_msg_id))
          actor.continue(
            RegistryState(
              ..state,
              messages: new_messages,
              next_message_id: state.next_message_id + 1,
            ),
          )
        }
        Error(_) -> {
          process.send(reply, Error("Original message not found"))
          actor.continue(state)
        }
      }
    }

    // ===== Statistics =====
    types.GetRegistryStats(reply) -> {
      let online_users =
        dict.values(state.users)
        |> list.filter(fn(user) { user.is_online })
        |> list.length

      let stats =
        RegistryStats(
          total_users: dict.size(state.users),
          online_users: online_users,
          total_subreddits: dict.size(state.subreddit_actors),
          total_messages: dict.size(state.messages),
        )

      process.send(reply, stats)
      actor.continue(state)
    }
  }
}

// Start the Registry Actor
pub fn start() -> Result(
  actor.Started(Subject(RegistryMessage)),
  actor.StartError,
) {
  let initial_state =
    RegistryState(
      users: dict.new(),
      subreddit_actors: dict.new(),
      messages: dict.new(),
      next_message_id: 1,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_registry_message)
  |> actor.start
}
