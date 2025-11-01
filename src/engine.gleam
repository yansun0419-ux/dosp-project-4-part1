// Reddit Engine Actor
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import types.{
  type Comment, type CommentId, type DirectMessage, type EngineState,
  type MessageId, type Post, type PostId, type Subreddit, type SubredditName,
  type User, type UserId, Comment, DirectMessage, EngineState, Post, Subreddit,
  User,
}

// Messages that the engine can receive
pub type EngineMessage {
  // User operations
  RegisterUser(username: String, reply: Subject(Result(UserId, String)))
  GetUser(user_id: UserId, reply: Subject(Result(User, String)))
  SetUserOnline(
    user_id: UserId,
    is_online: Bool,
    reply: Subject(Result(Nil, String)),
  )

  // Subreddit operations
  CreateSubreddit(
    name: SubredditName,
    creator: UserId,
    reply: Subject(Result(Nil, String)),
  )
  JoinSubreddit(
    user_id: UserId,
    subreddit: SubredditName,
    reply: Subject(Result(Nil, String)),
  )
  LeaveSubreddit(
    user_id: UserId,
    subreddit: SubredditName,
    reply: Subject(Result(Nil, String)),
  )
  GetSubreddit(name: SubredditName, reply: Subject(Result(Subreddit, String)))

  // Post operations
  CreatePost(
    author: UserId,
    subreddit: SubredditName,
    title: String,
    content: String,
    reply: Subject(Result(PostId, String)),
  )
  GetPost(post_id: PostId, reply: Subject(Result(Post, String)))
  VotePost(
    post_id: PostId,
    user_id: UserId,
    is_upvote: Bool,
    reply: Subject(Result(Nil, String)),
  )
  GetFeed(user_id: UserId, reply: Subject(Result(List(Post), String)))

  // Comment operations
  CreateComment(
    author: UserId,
    post_id: PostId,
    parent_comment_id: option.Option(CommentId),
    content: String,
    reply: Subject(Result(CommentId, String)),
  )
  GetComment(comment_id: CommentId, reply: Subject(Result(Comment, String)))
  VoteComment(
    comment_id: CommentId,
    user_id: UserId,
    is_upvote: Bool,
    reply: Subject(Result(Nil, String)),
  )
  GetPostComments(
    post_id: PostId,
    reply: Subject(Result(List(Comment), String)),
  )

  // Direct message operations
  SendDirectMessage(
    from: UserId,
    to: UserId,
    content: String,
    reply: Subject(Result(MessageId, String)),
  )
  GetDirectMessages(
    user_id: UserId,
    reply: Subject(Result(List(DirectMessage), String)),
  )
  ReplyToDirectMessage(
    message_id: MessageId,
    from: UserId,
    content: String,
    reply: Subject(Result(MessageId, String)),
  )

  // Stats
  GetStats(reply: Subject(EngineStats))
  Shutdown
}

pub type EngineStats {
  EngineStats(
    total_users: Int,
    online_users: Int,
    total_subreddits: Int,
    total_posts: Int,
    total_comments: Int,
    total_messages: Int,
  )
}

// Initialize engine state
fn init_state() -> EngineState {
  EngineState(
    users: dict.new(),
    subreddits: dict.new(),
    posts: dict.new(),
    comments: dict.new(),
    messages: dict.new(),
    next_post_id: 1,
    next_comment_id: 1,
    next_message_id: 1,
  )
}

// Get current timestamp (simplified)
fn now() -> Int {
  // In real implementation, use proper timestamp
  0
}

// Calculate user karma
fn calculate_karma(state: EngineState, user_id: UserId) -> Int {
  let post_karma =
    state.posts
    |> dict.values
    |> list.filter(fn(post) { post.author == user_id })
    |> list.fold(0, fn(acc, post) { acc + post.upvotes - post.downvotes })

  let comment_karma =
    state.comments
    |> dict.values
    |> list.filter(fn(comment) { comment.author == user_id })
    |> list.fold(0, fn(acc, comment) {
      acc + comment.upvotes - comment.downvotes
    })

  post_karma + comment_karma
}

// Handle engine messages
fn handle_message(
  state: EngineState,
  message: EngineMessage,
) -> actor.Next(EngineState, EngineMessage) {
  case message {
    RegisterUser(username, reply) -> {
      let user_id =
        "user_" <> username <> "_" <> string.inspect(dict.size(state.users))

      case dict.has_key(state.users, user_id) {
        True -> {
          process.send(reply, Error("User already exists"))
          actor.continue(state)
        }
        False -> {
          let user =
            User(
              id: user_id,
              username: username,
              karma: 0,
              subscribed_subreddits: [],
              is_online: True,
            )
          let new_state =
            EngineState(..state, users: dict.insert(state.users, user_id, user))
          process.send(reply, Ok(user_id))
          actor.continue(new_state)
        }
      }
    }

    GetUser(user_id, reply) -> {
      case dict.get(state.users, user_id) {
        Ok(user) -> {
          let karma = calculate_karma(state, user_id)
          let updated_user = User(..user, karma: karma)
          process.send(reply, Ok(updated_user))
        }
        Error(_) -> process.send(reply, Error("User not found"))
      }
      actor.continue(state)
    }

    SetUserOnline(user_id, is_online, reply) -> {
      case dict.get(state.users, user_id) {
        Ok(user) -> {
          let updated_user = User(..user, is_online: is_online)
          let new_state =
            EngineState(
              ..state,
              users: dict.insert(state.users, user_id, updated_user),
            )
          process.send(reply, Ok(Nil))
          actor.continue(new_state)
        }
        Error(_) -> {
          process.send(reply, Error("User not found"))
          actor.continue(state)
        }
      }
    }

    CreateSubreddit(name, creator, reply) -> {
      case dict.has_key(state.subreddits, name) {
        True -> {
          process.send(reply, Error("Subreddit already exists"))
          actor.continue(state)
        }
        False -> {
          let subreddit =
            Subreddit(
              name: name,
              creator: creator,
              members: [creator],
              posts: [],
              created_at: now(),
            )
          let new_state =
            EngineState(
              ..state,
              subreddits: dict.insert(state.subreddits, name, subreddit),
            )

          // Add subreddit to user's subscriptions
          case dict.get(state.users, creator) {
            Ok(user) -> {
              let updated_user =
                User(..user, subscribed_subreddits: [
                  name,
                  ..user.subscribed_subreddits
                ])
              let final_state =
                EngineState(
                  ..new_state,
                  users: dict.insert(new_state.users, creator, updated_user),
                )
              process.send(reply, Ok(Nil))
              actor.continue(final_state)
            }
            Error(_) -> {
              process.send(reply, Error("Creator not found"))
              actor.continue(state)
            }
          }
        }
      }
    }

    JoinSubreddit(user_id, subreddit_name, reply) -> {
      case dict.get(state.subreddits, subreddit_name) {
        Ok(subreddit) -> {
          case list.contains(subreddit.members, user_id) {
            True -> {
              process.send(reply, Error("Already a member"))
              actor.continue(state)
            }
            False -> {
              let updated_subreddit =
                Subreddit(..subreddit, members: [user_id, ..subreddit.members])
              let new_state =
                EngineState(
                  ..state,
                  subreddits: dict.insert(
                    state.subreddits,
                    subreddit_name,
                    updated_subreddit,
                  ),
                )

              // Update user's subscriptions
              case dict.get(state.users, user_id) {
                Ok(user) -> {
                  let updated_user =
                    User(..user, subscribed_subreddits: [
                      subreddit_name,
                      ..user.subscribed_subreddits
                    ])
                  let final_state =
                    EngineState(
                      ..new_state,
                      users: dict.insert(new_state.users, user_id, updated_user),
                    )
                  process.send(reply, Ok(Nil))
                  actor.continue(final_state)
                }
                Error(_) -> {
                  process.send(reply, Error("User not found"))
                  actor.continue(state)
                }
              }
            }
          }
        }
        Error(_) -> {
          process.send(reply, Error("Subreddit not found"))
          actor.continue(state)
        }
      }
    }

    LeaveSubreddit(user_id, subreddit_name, reply) -> {
      case dict.get(state.subreddits, subreddit_name) {
        Ok(subreddit) -> {
          let updated_subreddit =
            Subreddit(
              ..subreddit,
              members: list.filter(subreddit.members, fn(id) { id != user_id }),
            )
          let new_state =
            EngineState(
              ..state,
              subreddits: dict.insert(
                state.subreddits,
                subreddit_name,
                updated_subreddit,
              ),
            )

          // Update user's subscriptions
          case dict.get(state.users, user_id) {
            Ok(user) -> {
              let updated_user =
                User(
                  ..user,
                  subscribed_subreddits: list.filter(
                    user.subscribed_subreddits,
                    fn(name) { name != subreddit_name },
                  ),
                )
              let final_state =
                EngineState(
                  ..new_state,
                  users: dict.insert(new_state.users, user_id, updated_user),
                )
              process.send(reply, Ok(Nil))
              actor.continue(final_state)
            }
            Error(_) -> {
              process.send(reply, Error("User not found"))
              actor.continue(state)
            }
          }
        }
        Error(_) -> {
          process.send(reply, Error("Subreddit not found"))
          actor.continue(state)
        }
      }
    }

    GetSubreddit(name, reply) -> {
      case dict.get(state.subreddits, name) {
        Ok(subreddit) -> process.send(reply, Ok(subreddit))
        Error(_) -> process.send(reply, Error("Subreddit not found"))
      }
      actor.continue(state)
    }

    CreatePost(author, subreddit_name, title, content, reply) -> {
      case dict.get(state.subreddits, subreddit_name) {
        Ok(subreddit) -> {
          case list.contains(subreddit.members, author) {
            False -> {
              process.send(reply, Error("Must be a member to post"))
              actor.continue(state)
            }
            True -> {
              let post_id = "post_" <> string.inspect(state.next_post_id)
              let post =
                Post(
                  id: post_id,
                  author: author,
                  subreddit: subreddit_name,
                  title: title,
                  content: content,
                  upvotes: 0,
                  downvotes: 0,
                  comments: [],
                  created_at: now(),
                )

              let updated_subreddit =
                Subreddit(..subreddit, posts: [post_id, ..subreddit.posts])

              let new_state =
                EngineState(
                  ..state,
                  posts: dict.insert(state.posts, post_id, post),
                  subreddits: dict.insert(
                    state.subreddits,
                    subreddit_name,
                    updated_subreddit,
                  ),
                  next_post_id: state.next_post_id + 1,
                )

              process.send(reply, Ok(post_id))
              actor.continue(new_state)
            }
          }
        }
        Error(_) -> {
          process.send(reply, Error("Subreddit not found"))
          actor.continue(state)
        }
      }
    }

    GetPost(post_id, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> process.send(reply, Ok(post))
        Error(_) -> process.send(reply, Error("Post not found"))
      }
      actor.continue(state)
    }

    VotePost(post_id, _user_id, is_upvote, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          let updated_post = case is_upvote {
            True -> Post(..post, upvotes: post.upvotes + 1)
            False -> Post(..post, downvotes: post.downvotes + 1)
          }
          let new_state =
            EngineState(
              ..state,
              posts: dict.insert(state.posts, post_id, updated_post),
            )
          process.send(reply, Ok(Nil))
          actor.continue(new_state)
        }
        Error(_) -> {
          process.send(reply, Error("Post not found"))
          actor.continue(state)
        }
      }
    }

    GetFeed(user_id, reply) -> {
      case dict.get(state.users, user_id) {
        Ok(user) -> {
          let feed =
            state.posts
            |> dict.values
            |> list.filter(fn(post) {
              list.contains(user.subscribed_subreddits, post.subreddit)
            })
            |> list.take(50)
          // Limit to 50 posts

          process.send(reply, Ok(feed))
        }
        Error(_) -> process.send(reply, Error("User not found"))
      }
      actor.continue(state)
    }

    CreateComment(author, post_id, parent_comment_id, content, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          let comment_id = "comment_" <> string.inspect(state.next_comment_id)
          let comment =
            Comment(
              id: comment_id,
              author: author,
              post_id: post_id,
              parent_comment_id: parent_comment_id,
              content: content,
              upvotes: 0,
              downvotes: 0,
              replies: [],
              created_at: now(),
            )

          let updated_post =
            Post(..post, comments: [comment_id, ..post.comments])

          // Update parent comment if it exists
          let new_comments = case parent_comment_id {
            Some(parent_id) -> {
              case dict.get(state.comments, parent_id) {
                Ok(parent) -> {
                  let updated_parent =
                    Comment(..parent, replies: [comment_id, ..parent.replies])
                  dict.insert(state.comments, parent_id, updated_parent)
                }
                Error(_) -> state.comments
              }
            }
            None -> state.comments
          }

          let new_state =
            EngineState(
              ..state,
              comments: dict.insert(new_comments, comment_id, comment),
              posts: dict.insert(state.posts, post_id, updated_post),
              next_comment_id: state.next_comment_id + 1,
            )

          process.send(reply, Ok(comment_id))
          actor.continue(new_state)
        }
        Error(_) -> {
          process.send(reply, Error("Post not found"))
          actor.continue(state)
        }
      }
    }

    GetComment(comment_id, reply) -> {
      case dict.get(state.comments, comment_id) {
        Ok(comment) -> process.send(reply, Ok(comment))
        Error(_) -> process.send(reply, Error("Comment not found"))
      }
      actor.continue(state)
    }

    VoteComment(comment_id, _user_id, is_upvote, reply) -> {
      case dict.get(state.comments, comment_id) {
        Ok(comment) -> {
          let updated_comment = case is_upvote {
            True -> Comment(..comment, upvotes: comment.upvotes + 1)
            False -> Comment(..comment, downvotes: comment.downvotes + 1)
          }
          let new_state =
            EngineState(
              ..state,
              comments: dict.insert(state.comments, comment_id, updated_comment),
            )
          process.send(reply, Ok(Nil))
          actor.continue(new_state)
        }
        Error(_) -> {
          process.send(reply, Error("Comment not found"))
          actor.continue(state)
        }
      }
    }

    GetPostComments(post_id, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          let comments =
            post.comments
            |> list.filter_map(fn(comment_id) {
              dict.get(state.comments, comment_id)
            })

          process.send(reply, Ok(comments))
        }
        Error(_) -> process.send(reply, Error("Post not found"))
      }
      actor.continue(state)
    }

    SendDirectMessage(from, to, content, reply) -> {
      case dict.get(state.users, to) {
        Ok(_) -> {
          let message_id = "msg_" <> string.inspect(state.next_message_id)
          let message =
            DirectMessage(
              id: message_id,
              from: from,
              to: to,
              content: content,
              read: False,
              created_at: now(),
            )

          let new_state =
            EngineState(
              ..state,
              messages: dict.insert(state.messages, message_id, message),
              next_message_id: state.next_message_id + 1,
            )

          process.send(reply, Ok(message_id))
          actor.continue(new_state)
        }
        Error(_) -> {
          process.send(reply, Error("Recipient not found"))
          actor.continue(state)
        }
      }
    }

    GetDirectMessages(user_id, reply) -> {
      let messages =
        state.messages
        |> dict.values
        |> list.filter(fn(msg) { msg.to == user_id || msg.from == user_id })

      process.send(reply, Ok(messages))
      actor.continue(state)
    }

    ReplyToDirectMessage(message_id, from, content, reply) -> {
      case dict.get(state.messages, message_id) {
        Ok(original_msg) -> {
          let to = case original_msg.from == from {
            True -> original_msg.to
            False -> original_msg.from
          }

          let new_message_id = "msg_" <> string.inspect(state.next_message_id)
          let message =
            DirectMessage(
              id: new_message_id,
              from: from,
              to: to,
              content: content,
              read: False,
              created_at: now(),
            )

          let new_state =
            EngineState(
              ..state,
              messages: dict.insert(state.messages, new_message_id, message),
              next_message_id: state.next_message_id + 1,
            )

          process.send(reply, Ok(new_message_id))
          actor.continue(new_state)
        }
        Error(_) -> {
          process.send(reply, Error("Original message not found"))
          actor.continue(state)
        }
      }
    }

    GetStats(reply) -> {
      let online_count =
        state.users
        |> dict.values
        |> list.filter(fn(user) { user.is_online })
        |> list.length

      let stats =
        EngineStats(
          total_users: dict.size(state.users),
          online_users: online_count,
          total_subreddits: dict.size(state.subreddits),
          total_posts: dict.size(state.posts),
          total_comments: dict.size(state.comments),
          total_messages: dict.size(state.messages),
        )

      process.send(reply, stats)
      actor.continue(state)
    }

    Shutdown -> {
      actor.stop()
    }
  }
}

// Start the engine actor
pub fn start() -> Result(
  actor.Started(Subject(EngineMessage)),
  actor.StartError,
) {
  actor.new(init_state())
  |> actor.on_message(handle_message)
  |> actor.start
}

// Helper functions for synchronous calls
pub fn call(
  engine: Subject(EngineMessage),
  make_message: fn(Subject(t)) -> EngineMessage,
) -> t {
  process.call(engine, 5000, make_message)
}
