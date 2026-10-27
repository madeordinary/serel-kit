---
description: Post a GitHub comment or reply on the user's behalf, with an attribution callout, evidence, and a returned URL. Use for every comment an agent posts.
---

# /pr-comment

Rules for every comment you post on GitHub on the user's behalf. Follow them
whether the user asked for the comment directly or another workflow needs one:
`/file-pr`, `/babysit-pr`, and `/modernize-pr` point here, at
`.agents/skills/pr-comment/SKILL.md`, which carries the same rules.

Usage:

```text
/pr-comment 482 "the retry change is intentional; see the linked issue"
/pr-comment https://github.com/acme/shop/pull/482#discussion_r1234567
/pr-comment                     # then say what to reply to, and the gist
```

## Trigger

Use it for anything posted under the user's account on a pull request:
top-level comments, inline review comments, replies to reviewers or bots, and
the written reason given before resolving or dismissing a thread.

Do not use it for PR descriptions, commit messages, or text the user asked to
post word for word without attribution. Do not post a comment nobody needs:
if neither the user nor the calling workflow asked for one, say nothing.

## Required reads

1. The thing you are answering: the comment or thread, and the code, check,
   or log it is about. Read the current code, not the version the comment saw.
2. Your evidence: the file and line, the check run and its link, or the
   command you ran and its result.
3. The public model name your harness reports, and the user's name or GitHub
   login (`gh api user --jq .login`). If the harness reports no model name,
   use the harness name. Never guess a model.
4. The whole draft, quoted text and attachments included, before you post it.

## Allowed writes

- One comment or reply per request, posted with `gh` from a body file so
  quoting and blank lines survive: `gh pr comment <pr> --body-file <file>`
  for a top-level comment, or
  `gh api repos/<owner>/<repo>/pulls/<pr>/comments/<id>/replies -F body=@<file>`
  for a reply in a review thread. The body file is a temporary file outside
  the repository.
- Resolving the review thread the reply answers, only after GitHub returned
  the reply's URL. Leave a person's thread for that person to resolve unless
  the user says otherwise.

If the user asked for this comment, or the calling workflow's request covers
it, post without asking again. Otherwise show the draft and ask first.

## The format

Every comment starts with this GitHub note callout, then a blank line, then
the comment itself:

```md
> [!NOTE]
> 🤖 **<model> responding on behalf of <user>**

<the comment>
```

- The attribution stays inside the note; the comment stays outside it.
- The context line starts with the robot emoji.
- No horizontal rule, Setext underline, heading, signature, or second
  attribution.

## Writing the comment

- Lead with the conclusion: fixed, declined, or a question.
- Cite the evidence: `src/cart.ts:88`, the check name and its link, or the
  reproduction and what it printed.
- Keep verified facts apart from judgment. "The test fails on main too" is a
  fact; "this looks like a flake" is a judgment, and reads as one.
- Be brief. No filler, canned thanks, or status narration such as "still
  waiting".
- Check the entire comment, quotes and attachments included, for secrets and
  private details: tokens, keys, internal URLs, personal data, and private
  memory bank content. Remove them, or stop and ask if removing one would
  change the meaning.

## Steps

1. Read what you are answering and gather the evidence.
2. Draft the comment in the format above, in a temporary body file.
3. Preview the final Markdown: the callout renders as a note, blank lines are
   where you meant them, and nothing secret or private remains.
4. Post it. Confirm GitHub returned the comment or review URL. No URL means
   it was not posted: say so, and check the PR before trying again so you do
   not post it twice.
5. Resolve the thread only if the reply posted and the thread is yours or a
   bot's to resolve.

## Output contract

```text
PR-COMMENT: <posted | not posted> — <PR or thread URL>
URL: <the URL GitHub returned> | none
RESOLVED: <thread URL> | no
```

When it was not posted, add one line saying why.

## Stop conditions

Stop and ask when:

- `gh` is missing or not authenticated (`gh auth status`).
- Nobody asked for a comment, and none is needed to do what the user asked.
- Removing a secret or private detail would change what the comment says.
- The comment would state something you could not verify. Ask, or say it
  plainly as unverified.
- GitHub returned no URL. Do not resolve the thread, and do not retry in a
  loop.
