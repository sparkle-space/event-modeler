---
name: gh-comment-review
description: Review GitHub PR comments, implement relevant suggestions, dismiss irrelevant ones, resolve threads, and return a summary table. Use when a PR has review comments to address.
---

# /gh-comment-review — GitHub PR Comment Review

Review all comments on a GitHub PR, evaluate each one, implement relevant changes, dismiss irrelevant ones, resolve all threads, and return a summary.

## Arguments

- First argument: PR number (e.g., `/gh-comment-review 96`). If omitted, detect from current branch using `gh pr view --json number`.

## Process

### 1. Identify the PR

```bash
# If no PR number given, detect from current branch
gh pr view --json number -q .number
```

### 2. Fetch All Review Comments

Use the GitHub REST API to get review comments (inline code comments):

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments
```

Also fetch top-level PR review bodies:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews
```

Extract from each comment:
- `id` — comment ID
- `path` — file path
- `line` — line number
- `body` — the comment text
- `user.login` — who left the comment
- `in_reply_to_id` — if this is a reply (skip replies, they're follow-ups)

### 3. Evaluate Each Comment

For each top-level comment (not a reply), evaluate:

1. **Read the referenced file** at the specified path and line to understand context
2. **Assess relevance**: Is the suggestion valid? Does it improve the code?
3. **Decide action**:
   - **Implement** — if the suggestion fixes a real bug, improves correctness, or meaningfully improves UX/DX
   - **Dismiss** — if the suggestion is stylistic preference, over-engineering, not applicable to this codebase's conventions, or would introduce unnecessary complexity

**Dismissal criteria** — dismiss comments that:
- Suggest adding complexity for hypothetical future scenarios
- Propose patterns inconsistent with the codebase conventions (check CLAUDE.md)
- Are duplicates of another comment (address the root once)
- Are purely stylistic with no functional impact
- Come from automated bots with low-confidence suggestions

**Implementation criteria** — implement comments that:
- Fix actual bugs or incorrect behavior
- Address real UX issues users would encounter
- Improve correctness or security
- Are consistent with codebase conventions

### 4. Implement Relevant Changes

For each comment to implement:
1. Read the file
2. Make the change (use Edit tool)
3. Ensure the fix is clean and follows project conventions

After all changes:
```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

### 5. Update Event Models (if affected)

If any implemented change affects routes, navigation, commands, events, or views documented in `priv/event_models/`, update the relevant event model document.

### 6. Resolve All Threads

Use the GitHub GraphQL API to resolve each review thread:

First, get thread IDs:
```bash
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 50) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { body }
          }
        }
      }
    }
  }
}'
```

Then resolve each unresolved thread:
```bash
gh api graphql -f query='mutation {
  resolveReviewThread(input: {threadId: "THREAD_ID"}) {
    thread { isResolved }
  }
}'
```

### 7. Commit Changes (if any)

If changes were implemented, commit with a message like:
```
Address PR review: <brief summary of changes>
```

### 8. Output Summary

Return a markdown table summarizing all comments:

```markdown
| # | Comment | File | Action | Details |
|---|---------|------|--------|---------|
| 1 | Short description | path:line | Implemented / Dismissed | What changed or why dismissed |
| 2 | ... | ... | ... | ... |
```

If changes were committed, note the commit hash. If the branch needs pushing, mention it.
