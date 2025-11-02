// Subreddit Actor - Independent Engine for Each Subreddit
// One instance per subreddit, handles all operations within that subreddit

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import types.{
  type Comment, type CommentId, type Post, type PostId, type Subreddit,
  type SubredditMessage, type SubredditName, type SubredditState,
  type SubredditStats, type UserId, Comment, Post, Subreddit, SubredditState,
  SubredditStats,
}

// Handle Subreddit messages
fn handle_subreddit_message(
  state: SubredditState,
  message: SubredditMessage,
) -> actor.Next(SubredditState, SubredditMessage) {
  case message {
    // ===== Member Management =====
    types.JoinSubreddit(user_id, reply) -> {
      case list.contains(state.members, user_id) {
        True -> {
          process.send(reply, Error("Already a member"))
          actor.continue(state)
        }
        False -> {
          let new_members = [user_id, ..state.members]
          process.send(reply, Ok(Nil))
          actor.continue(SubredditState(..state, members: new_members))
        }
      }
    }

    types.LeaveSubreddit(user_id, reply) -> {
      let new_members = list.filter(state.members, fn(id) { id != user_id })
      process.send(reply, Ok(Nil))
      actor.continue(SubredditState(..state, members: new_members))
    }

    types.GetSubredditInfo(reply) -> {
      let post_ids = dict.keys(state.posts)

      let subreddit_info =
        Subreddit(
          name: state.name,
          creator: state.creator,
          members: state.members,
          posts: post_ids,
          created_at: state.created_at,
        )

      process.send(reply, Ok(subreddit_info))
      actor.continue(state)
    }

    // ===== Post Operations =====
    types.CreatePost(author, title, content, reply) -> {
      let post_id = state.name <> "_post_" <> string.inspect(state.next_post_id)

      let new_post =
        Post(
          id: post_id,
          author: author,
          subreddit: state.name,
          title: title,
          content: content,
          upvotes: 0,
          downvotes: 0,
          comments: [],
          created_at: 0,
        )

      let new_posts = dict.insert(state.posts, post_id, new_post)

      process.send(reply, Ok(post_id))
      actor.continue(
        SubredditState(
          ..state,
          posts: new_posts,
          next_post_id: state.next_post_id + 1,
        ),
      )
    }

    types.GetPost(post_id, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> process.send(reply, Ok(post))
        Error(_) -> process.send(reply, Error("Post not found"))
      }
      actor.continue(state)
    }

    types.VotePost(post_id, _user_id, is_upvote, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          let updated_post = case is_upvote {
            True -> Post(..post, upvotes: post.upvotes + 1)
            False -> Post(..post, downvotes: post.downvotes + 1)
          }

          let new_posts = dict.insert(state.posts, post_id, updated_post)

          // Update author's karma
          let karma_delta = case is_upvote {
            True -> 1
            False -> -1
          }
          process.send(
            state.registry,
            types.UpdateKarma(user_id: post.author, delta: karma_delta),
          )

          process.send(reply, Ok(Nil))
          actor.continue(SubredditState(..state, posts: new_posts))
        }
        Error(_) -> {
          process.send(reply, Error("Post not found"))
          actor.continue(state)
        }
      }
    }

    types.GetFeed(_user_id, reply) -> {
      // Return all posts (newest first)
      let posts = dict.values(state.posts)

      process.send(reply, Ok(posts))
      actor.continue(state)
    }

    // ===== Comment Operations =====
    types.CreateComment(author, post_id, parent_comment_id, content, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          let comment_id =
            state.name <> "_comment_" <> string.inspect(state.next_comment_id)

          let new_comment =
            Comment(
              id: comment_id,
              author: author,
              post_id: post_id,
              parent_comment_id: parent_comment_id,
              content: content,
              upvotes: 0,
              downvotes: 0,
              replies: [],
              created_at: 0,
            )

          let new_comments =
            dict.insert(state.comments, comment_id, new_comment)

          // Update post's comment list
          let updated_post =
            Post(..post, comments: [comment_id, ..post.comments])

          let new_posts = dict.insert(state.posts, post_id, updated_post)

          // If replying to a comment, update parent comment
          let final_comments = case parent_comment_id {
            Some(parent_id) -> {
              case dict.get(new_comments, parent_id) {
                Ok(parent_comment) -> {
                  let updated_parent =
                    Comment(..parent_comment, replies: [
                      comment_id,
                      ..parent_comment.replies
                    ])

                  dict.insert(new_comments, parent_id, updated_parent)
                }
                Error(_) -> new_comments
              }
            }
            None -> new_comments
          }

          process.send(reply, Ok(comment_id))
          actor.continue(
            SubredditState(
              ..state,
              posts: new_posts,
              comments: final_comments,
              next_comment_id: state.next_comment_id + 1,
            ),
          )
        }
        Error(_) -> {
          process.send(reply, Error("Post not found"))
          actor.continue(state)
        }
      }
    }

    types.GetComment(comment_id, reply) -> {
      case dict.get(state.comments, comment_id) {
        Ok(comment) -> process.send(reply, Ok(comment))
        Error(_) -> process.send(reply, Error("Comment not found"))
      }
      actor.continue(state)
    }

    types.VoteComment(comment_id, _user_id, is_upvote, reply) -> {
      case dict.get(state.comments, comment_id) {
        Ok(comment) -> {
          let updated_comment = case is_upvote {
            True -> Comment(..comment, upvotes: comment.upvotes + 1)
            False -> Comment(..comment, downvotes: comment.downvotes + 1)
          }

          let new_comments =
            dict.insert(state.comments, comment_id, updated_comment)

          // Update author's karma
          let karma_delta = case is_upvote {
            True -> 1
            False -> -1
          }
          process.send(
            state.registry,
            types.UpdateKarma(user_id: comment.author, delta: karma_delta),
          )

          process.send(reply, Ok(Nil))
          actor.continue(SubredditState(..state, comments: new_comments))
        }
        Error(_) -> {
          process.send(reply, Error("Comment not found"))
          actor.continue(state)
        }
      }
    }

    types.GetPostComments(post_id, reply) -> {
      case dict.get(state.posts, post_id) {
        Ok(post) -> {
          let comments =
            post.comments
            |> list.filter_map(fn(comment_id) {
              dict.get(state.comments, comment_id)
            })

          process.send(reply, Ok(comments))
          actor.continue(state)
        }
        Error(_) -> {
          process.send(reply, Error("Post not found"))
          actor.continue(state)
        }
      }
    }

    // ===== Statistics =====
    types.GetSubredditStats(reply) -> {
      let stats =
        SubredditStats(
          name: state.name,
          total_members: list.length(state.members),
          total_posts: dict.size(state.posts),
          total_comments: dict.size(state.comments),
        )

      process.send(reply, stats)
      actor.continue(state)
    }
  }
}

// Start a Subreddit Actor
pub fn start(
  name: SubredditName,
  creator: UserId,
  registry: Subject(types.RegistryMessage),
) -> Result(actor.Started(Subject(SubredditMessage)), actor.StartError) {
  let initial_state =
    SubredditState(
      name: name,
      creator: creator,
      members: [creator],
      posts: dict.new(),
      comments: dict.new(),
      next_post_id: 1,
      next_comment_id: 1,
      created_at: 0,
      registry: registry,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_subreddit_message)
  |> actor.start
}
