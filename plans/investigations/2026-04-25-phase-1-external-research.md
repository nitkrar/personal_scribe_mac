# Phase 1 — External research (raw evidence)

**Date:** 2026-04-25
**Companion summary:** `2026-04-25-agent-execution-retrospective.md` Part 1

This file persists the verbatim primary sources that fed the Five-Gaps analysis.

---

## 1. Matt Pocock — "Software Fundamentals Matter More Than Ever"

**Source:** `https://www.youtube.com/watch?v=v4F1gFy-hqg`
**Speaker:** Matt Pocock (creator of Total TypeScript, ex-XState, ex-Vercel DA)

### Transcript (verbatim, as pasted by user)

```
0:14
Hello everyone. Having a good conference
0:16
so far?
0:17
Are you having a good conference so far?
0:19
Good. Wonderful.
0:22
I have a message for you that I hope
0:24
will be um a comforting message for
0:27
folks who believe that uh their skill
0:30
set is no longer worth anything in this
0:32
new age, which is I believe that
0:34
software fundamentals matter now more
0:36
than they actually ever have.
0:39
And
0:40
I'm a teacher and I've been recently
0:44
teaching a course called Claude Code for
0:45
real engineers. Nice and provocative.
0:48
And in the process of kind of working on
0:50
this course, I had to come up with a
0:52
curriculum about AI coding, which is a
0:56
bit of a nightmare because things are
0:58
changing all the time, right? AI is a
1:00
whole new paradigm. We need to chuck out
1:03
all of the old rules surely so that we
1:05
can bring in the new stuff.
1:08
And there's a kind of movement that has
1:11
come up around this, which is the specs
1:14
to code movement. And the specs to code
1:16
movement says that okay you can write a
1:18
specification about how an application
1:19
is supposed to work then you can use AI
1:22
to turn it into code. If there's a
1:24
problem with the application you then go
1:26
back to the spec. You don't really look
1:28
at the code. You just change the spec.
1:29
You run the compiler again and you end
1:32
up with more code. Raise your hand if
1:35
you've heard of that. Keep your hand
1:37
raised if you've tried it. Okay. I've
1:40
tried it too. You can put your hands
1:41
down.
1:42
And what I noticed was I would run it
1:45
and I would try not to look at the code
1:48
but I would look at the code and I
1:50
realized I would get code out first of
1:52
all and then I would run it I would get
1:53
worse code and then I did it again I got
1:55
even worse code and I got it again I
1:58
kept running the compiler kept running
1:59
the compiler and I would just end up
2:00
with garbage.
2:03
You know raise your hand if that's
2:04
happened to you. Yes. I don't think this
2:08
works. the idea that we can just ignore
2:10
the code and just have the code let it
2:12
manage itself is just sort of v coding
2:14
by another name
2:16
and I didn't believe that back then I
2:19
thought okay how do I fix the compiler
2:21
how do I make it so that it doesn't
2:22
produce bad code each time or worse code
2:25
and so I thought okay I need to explain
2:27
to the LLM in English what a good
2:30
codebase looks like let me dig out one
2:33
of my old favorite books which is a
2:35
philosophy of software design by John
2:36
ouster go on Amazon get it. Um, and he
2:41
has a definition for what bad code looks
2:44
like. He calls it complex code.
2:46
Complexity is anything related to the
2:48
structure of a software system that
2:50
makes it hard to understand and modify
2:52
the system. Right? So, a a bad codebase
2:55
is a codebase that's hard to change. If
2:57
you can't change a codebase without
2:59
causing bugs, then it's a bad codebase.
3:01
Good code bases are easy to change. So,
3:04
I thought, oh, that was good. Let's try
3:06
another book. Let's try the paragmatic
3:07
programmer. Go on Amazon, get it. They
3:11
have a whole chapter on something called
3:12
software entropy. And this is exactly
3:15
what I was seeing. Entropy is the idea
3:17
that things tend towards um disaster and
3:20
uh floating away from each other and
3:22
collapse. And this is exactly how most
3:24
software systems behave too is that
3:26
every time you make a change to a
3:27
codebase, if you're only thinking about
3:29
that change, not thinking about the
3:30
design of the whole system, your
3:32
codebase is going to get worse and worse
3:34
and worse. And that's what I was seeing.
3:37
Everything inside the specs to code idea
3:39
that you just run the compiler again and
3:40
again was making worse code. Now there's
3:44
an idea that sort of drives the specs to
3:46
code movement which is that code is
3:49
cheap. Raise your hand if you've heard
3:51
that phrase before that code is cheap.
3:52
Yeah.
3:55
Well, I don't think this is right. I
3:57
think code is not cheap. In fact, bad
4:00
code is the most expensive it's ever
4:02
been. Because if you have a codebase
4:04
that's hard to change, you're not able
4:06
to take all of the bounty that AI can
4:09
offer because AI in a good codebase
4:12
actually does really, really well.
4:15
And this means good code bases matter
4:17
more than ever, which means software
4:18
fundamentals matter more than ever.
4:20
That's the thesis of this talk. So,
4:22
let's actually get into practical stuff.
4:25
I'm going to talk about different
4:26
failure modes that you may have
4:27
experienced or you may not have
4:29
experienced yet with AI and how you can
4:31
avoid them by just going back to old
4:33
books and looking at good software
4:34
practices. Sound good? So, the first one
4:37
is that the AI didn't do what I wanted.
4:40
You know, I I thought I had a good idea
4:42
in my head and the AI just did something
4:44
totally different or it did some uh like
4:46
specs that I you know, it just made
4:48
something I didn't want. Raise your hand
4:49
if you've hit this mode.
4:51
Cool. Okay. Well, this is what they say
4:55
in the pragmatic programmer is that no
4:57
one knows exactly what they want. Is
4:59
that you and the AI, there is a
5:01
communication barrier there, right? And
5:04
so when you're talking to the AI, that's
5:06
kind of like the AI doing its
5:07
requirements gathering. It's basically
5:09
working out from you what it is that you
5:11
need. And I realized that there was
5:15
another book, Frederick P. Brooks, the
5:17
design of design, and it talks about
5:19
this idea called the design concept. is
5:22
that when you have more than one person
5:24
designing something together, you have
5:26
this idea sort of floating between you,
5:28
this ephemeral idea of the thing that
5:30
you're building. And that thing that
5:32
you're building or the idea of it is
5:34
called the design concept. It's not an
5:36
asset. It's not something you can put in
5:37
a markdown file. It is the invisible
5:40
sort of theory of what you're building.
5:44
And so I thought, okay, that's what's
5:46
going on. Me and the AI don't share a
5:48
design concept. So I came up with a
5:50
skill. The skill is very very simple.
5:53
It's called grill me and it looks like
5:56
this. Interview me relentlessly about
5:58
every aspect of this plan until we reach
6:01
a shared understanding. Walk down each
6:04
branch of the design tree which is
6:05
another thing from Frederick P. Brooks
6:07
resolving dependencies between decisions
6:09
one by one. This skill is like uh the
6:12
repo containing this skill has like
6:13
13,000 stars or something like it just
6:15
went nuts. Went viral. People love this
6:17
thing. it. These couple of lines means
6:20
the AI asks you like 40 questions, 60
6:23
questions. I've had it ask uh people a
6:25
hundred questions before it's satisfied
6:27
they've reached a shared understanding.
6:29
And it means it turns the AI into a kind
6:32
of adversary where it's just continually
6:34
pinging you ideas and trying to reach a
6:36
shared understanding. And that means
6:38
that the conversation that you then
6:40
generate, you can take that and turn it
6:42
into a product requirements document or
6:44
something. or if it's a small change,
6:47
you can just uh do turn it directly into
6:50
issues and then your AFK agent will then
6:53
pick it up. And don't at me on this, but
6:56
I personally believe this is better than
6:58
the default plan mode in the tool that I
7:02
use, which is claw code. Plan mode is
7:05
extremely eager to create an asset. It
7:08
really wants to uh just create a plan
7:10
and start working. whereas I think it's
7:13
a lot nicer to reach a shared design
7:17
concept first. So that's tip number one.
7:21
Now failure mode number two is that the
7:22
AI is just way too verbose.
7:26
It's like you're almost talking across
7:27
purposes with the AI. Raise your hand if
7:29
you uh feel this. If you ever experience
7:32
that failure mode. Yeah. It's kind of
7:33
like the AI is like talking just using
7:35
too many words to try to communicate
7:37
what it's doing. It's not like you're
7:39
talking uh using the same language. And
7:42
this to me felt very very familiar.
7:44
Right? If you've ever been a developer
7:46
for a long time and you've worked with
7:48
let's say domain experts, someone
7:49
building an application um let's say the
7:52
domain expert wants you to build
7:53
something on uh I don't know microchips.
7:55
You have no idea what microchips are.
7:57
You need to establish some kind of
7:58
shared language, right? Because
8:00
otherwise they're going to be using
8:01
terms you don't understand. You're going
8:02
to be translating that into code that
8:04
maybe you don't even understand and
8:05
certainly the domain expert won't. And
8:07
so there's this kind of language gap
8:09
between you and the domain expert. And
8:13
so I went back to domain driven design.
8:16
DDD, this is something I'm still kind of
8:18
on the edge of exploring, but everything
8:20
I'm reading about DDD is just music to
8:23
my ears. I freaking love it. And DDD has
8:26
a concept of a ubiquitous language.
8:30
With ubiquitous language, conversations
8:33
among developers and expressions of the
8:35
code and conversations with domain
8:36
experts are all derived from the same
8:38
domain model. It's essentially a
8:40
markdown file full of a list of terms
8:42
that you and the AI have in common. And
8:44
you really focus on those terms and you
8:46
really make sure that they're aligned
8:48
with what it actually means and you use
8:50
them all the time in the code when
8:52
you're talking about the code when
8:53
you're talking to domain experts or in
8:55
our case when you're talking with AI. So
8:57
I made a skill. This skill is the
9:00
ubiquitous language skill. Basically
9:02
just scans your codebase, looks for
9:04
terminology, and then um creates a
9:08
markdown file. Creates the ubiquitous
9:10
language markdown file. A bunch of
9:11
markdown tables with all of the
9:13
terminology. And this then I pass it to
9:16
the AI and I'm able to read it to and I
9:19
actually have it open all the time when
9:21
I'm grilling with the AI and planning
9:22
and that. And what I noticed by reading
9:25
the thinking traces of the AI, it not
9:26
only improves the planning, but it
9:28
allows the AI to think in a less verbose
9:31
way and actually means that the
9:33
implementation is more aligned with what
9:35
you actually planned. So this has
9:38
absolutely been a powerhouse. It's been
9:39
unbelievably good. So that's tip number
9:42
two. Create a shared language with the
9:44
AI. So okay, let's imagine that you've
9:47
aligned with the AI. You know what it is
9:49
you're supposed to be building. the AI
9:51
has built the right thing, but it
9:54
doesn't work. Raise your hands if that's
9:56
happened to you. Yeah, just doesn't
9:58
work. Well, there's an obvious thing
10:00
that we can do to make that better,
10:03
which is we can use feedback loops. We
10:05
can use um static types. You know, if
10:07
you're not using TypeScript, u that's
10:09
crazy. Uh if you're not using uh if
10:12
you're building a front-end app and
10:13
you're not giving it the LM access to
10:15
the browser so it can look around,
10:17
absolutely needs that. And you obviously
10:20
also need automated tests.
10:23
And one sort of thing I notice here is
10:27
that even with these feedback loops, the
10:29
LLM doesn't use them very well. It
10:32
doesn't kind of like get the most out of
10:34
its feedback loops in the way that a
10:35
veteran developer would. And so it does
10:37
what it tends to do is just does way too
10:40
much at once. it will produce like huge
10:42
amounts of code and then think, "Oh, I
10:44
should probably type check that actually
10:46
or I should uh yeah, maybe check a test
10:48
on that or maybe do something like
10:49
that." And this in the pragmatic
10:52
programmer they describe as outrunning
10:53
your headlights as essentially driving
10:56
too fast because the rate of feedback is
11:00
your speed limit. The rate of feedback
11:03
is your speed limit, which means that
11:04
you should be testing as you go, taking
11:07
small deliberate steps. And the AI by
11:09
default is really not very good at that.
11:12
And so skill number three is TDD. You
11:15
should be using testdriven development
11:17
because TDD forces the LLM to really
11:22
take small steps. You create a test
11:24
first. You make that test pass and then
11:27
you refactor the code to make it nicer
11:29
and consider the design.
11:32
The issue here is that testing is really
11:35
hard. Testing has always been hard.
11:38
And the reason for that
11:41
is there are a ton of different
11:43
decisions you need to make when you
11:45
write a test. You need to figure out how
11:47
big a unit do you want to test. You need
11:50
to figure out what to mock. You need to
11:52
figure out what behaviors do you even
11:54
want to test in the first place. And all
11:56
of these decisions are dependent. So if
11:57
you are testing a really big unit like
11:59
an entire massive application, then it
12:02
might be quite flaky. You might not want
12:04
to test that many behaviors. you know,
12:06
if you only test this unit, you need to
12:08
mock this unit. You know, it's all
12:09
interlin. And I've been thinking about
12:11
this for years for my entire development
12:13
career.
12:15
And what we notice is that good code
12:18
bases are easy code bases to test,
12:20
right? So, here we're starting to get
12:22
back to the idea of code being important
12:25
is that the better your codebase is, the
12:27
better your feedback loops are. Because
12:29
you're able to um give better feedback
12:32
to the LM, it produces better code.
12:35
And so I thought what does a good
12:37
codebase what does a testable codebase
12:38
look like? Again we go to John erhout.
12:42
He talks about having deep modules in
12:45
your codebase. Not shallow modules not
12:48
lots of modules that expose like kind of
12:50
um lots of functions. They should be
12:53
relatively few large deep modules with
12:55
simple interfaces. Let's compare them
12:58
quickly.
12:59
Deep modules, lots of functionality
13:01
hidden behind a simple interface, hiding
13:04
the complexity. You can look inside the
13:06
deep module if you want to, but you
13:07
don't need to. You can just use the
13:09
interface. Shallow modules, not much
13:11
functionality, complex interface.
13:14
And I'll just wait for you to take the
13:16
photos.
13:18
Shallow modules in a codebase kind of
13:20
look like this, where you have a ton of
13:22
different tiny little blobs that the AI
13:24
has to walk through and navigate. And
13:27
this is really hard for the AI to
13:29
explore actually. And so often what
13:31
you'll see is if you have a codebase
13:33
like this, which AI is really good at
13:34
creating code bases like this is that
13:37
you'll have a situation where AI doesn't
13:39
understand what your code is doing. It
13:41
will attempt to explore the code, but
13:43
because it's poorly laid out, filled
13:45
with shallow modules, it doesn't maybe
13:47
get to the right module in time or
13:49
doesn't understand all the dependencies,
13:50
all that stuff. It doesn't understand
13:52
your code. And so what does a codebase
13:55
full of deep modules look like? Well, it
13:58
looks like this
14:00
where it's the same code, but it's just
14:02
structured inside boundaries where you
14:04
have these interfaces on the top.
14:08
And these interfaces, you should
14:10
probably have a lot of control over them
14:12
and design them really well. Otherwise,
14:14
you know, AI might mess up the design.
14:17
But the implementation, you can kind of
14:18
leave that to the AI a bit.
14:21
So, how do you turn a codebase that
14:23
looks like this into a codebase that
14:26
looks like that? Well, I've got a skill
14:30
for that. Improve codebase architecture.
14:32
Turns out this is not it's quite
14:34
complicated to do this, but it's a like
14:37
a set of steps that you can reusably do
14:39
again and again. You just sort of
14:41
explore the codebase, look for
14:42
opportunities where there's code that's
14:44
kind of um related, and wrap all of that
14:47
in a deep module.
14:50
And this is a testable codebase because
14:52
the boundaries around this code are so
14:54
so simple. You test at the interface,
14:57
you verify using that interface and
14:59
you're good to go. And so this is a
15:00
codebase that rewards TDD.
15:04
But how about failure bone number six,
15:06
which is your okay, let's say your
15:08
feedback loops are working. Let's say
15:09
that things are kicking into gear.
15:11
You're able to ship more code than you
15:12
ever have before, but your brain can't
15:15
keep up, right? Uh, raise your hand if
15:18
you felt more tired than you have ever
15:20
before in your development career. Yeah,
15:22
me too. It's knackering. And I think
15:26
that this is a codebase that actually
15:28
makes it harder for your brain because
15:30
you as well as the AI need to keep all
15:32
of that information in your head.
15:34
Whereas this, not only is it simpler
15:38
for you to read and understand, it also
15:40
means you can kind of treat these
15:42
modules or these deep modules as gray
15:45
boxes.
15:47
you can kind of say okay I'm going to
15:51
just design the interface but I'm not
15:52
going to worry too much or not review
15:54
the implementation too much you can do
15:57
this obviously with uh things that are
15:58
less critical in your application can't
16:00
do this with uh you know various things
16:02
like finance or whatever but in many
16:05
many modules in your app you don't need
16:07
to think about the implementation too
16:08
much as long as you have a testable
16:10
boundary outside the module and as long
16:12
as you understand its purpose and can
16:14
design it from the outside I have found
16:16
this has really saved my brain because I
16:18
can just go okay the AI I'll let you
16:21
handle what's inside the big blob I'm
16:23
just going to test from the outside and
16:24
verify it so that's tip number five
16:27
design the interface delegate the
16:29
implementation
16:32
but this means that whenever we're
16:34
touching the code whenever we're
16:35
planning stuff we need to think about
16:37
and be aware of the modules in our
16:39
application we need to know that map
16:41
really well it needs to be part of our
16:43
ubiquitous language we need to build
16:45
into our planning skills as well. So my
16:48
writer PRD inside the PRD I'm specific
16:50
about the module changes and the
16:52
interfaces inside those modules how
16:54
they're being modified. I'm thinking
16:55
about them all the time. And this comes
16:57
from Kent Beck. Invest in the design of
17:00
the system every day. And this is the
17:03
core of it right because specs the code
17:05
we are not investing in the design of
17:07
the system we are divesting from it.
17:10
We're getting rid of that. Whereas this
17:12
I think is absolutely key.
17:16
And so code is not cheap. That's the
17:19
message I want you to take away. Code is
17:21
important.
17:23
And if we think about AI as a really
17:25
great on the ground programmer, a kind
17:28
of tactical programmer, a sergeant on
17:30
the ground making the code changes, you
17:33
need someone above that. You need
17:35
someone thinking on the strategic level
17:38
and that's you. And that requires
17:40
software fundamental skills that we've
17:42
been using for 20 years for longer.
17:46
Now, if you are interested in any of the
17:48
skills I put up here, it's in the GitHub
17:50
repo, Mac PCO skills. And if you're
17:52
interested in the training that I do or
17:54
uh any free stuff, I'm on YouTube, I'm
17:56
on Twitter, but I'm also at aihero.dev
17:58
where I have a newsletter that you can
18:00
check out. Thank you so much. I hope
18:02
that this gives you confidence in this
18:04
new AI age that you can actually make a
18:06
good impact. Thank you.
```

### Books referenced

- **John Ousterhout — *A Philosophy of Software Design*** (deep modules vs shallow modules; complexity definition)
- **The Pragmatic Programmer** (software entropy; "outrunning your headlights")
- **Frederick P. Brooks — *The Design of Design*** (the design concept; design tree)
- **Domain-Driven Design** (ubiquitous language)
- **Kent Beck** (invest in design every day)

---

## 2. `mattpocock/skills` GitHub repo

**URL:** `https://github.com/mattpocock/skills`
**Stars:** 18.2k (as of 2026-04-25 fetch)
**Description:** "A collection of agent skills that extend capabilities across planning, development, and tooling."

### Skill index (16 skills)

**Planning & Design**
- `to-prd` — Synthesize conversation context into a PRD and submit as a GitHub issue
- `to-issues` — Break plans/specs into independently-grabbable GitHub issues using vertical slices
- `grill-me` — Conduct thorough interviews about plans until all decision branches are resolved
- `design-an-interface` — Generate multiple radically different interface designs using parallel sub-agents
- `request-refactor-plan` — Create detailed refactor plans with tiny commits via user interview

**Development**
- `tdd` — Test-driven development with red-green-refactor loop for features or bug fixes
- `triage-issue` — Investigate bugs, identify root causes, and file issues with TDD-based fix plans
- `improve-codebase-architecture` — Find architectural improvement opportunities informed by domain language
- `migrate-to-shoehorn` — Migrate test files from type assertions to @total-typescript/shoehorn
- `scaffold-exercises` — Create exercise directory structures with sections, problems, and solutions

**Tooling & Setup**
- `setup-pre-commit` — Configure Husky pre-commit hooks with linting, formatting, and testing
- `git-guardrails-claude-code` — Set up Claude Code hooks to block dangerous git commands

**Writing & Knowledge**
- `write-a-skill` — Create new skills with proper structure and bundled resources
- `edit-article` — Improve articles through restructuring, clarity, and prose refinement
- `ubiquitous-language` — Extract DDD-style glossaries from conversations
- `obsidian-vault` — Search, create, and manage notes in Obsidian vaults with wikilinks

### Skill #1 — `grill-me/SKILL.md` (verbatim)

```markdown
---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.
```

### Skill #2 — `ubiquitous-language/SKILL.md` (verbatim)

```markdown
---
name: ubiquitous-language
description: Extract a DDD-style ubiquitous language glossary from the current conversation, flagging ambiguities and proposing canonical terms. Saves to UBIQUITOUS_LANGUAGE.md. Use when user wants to define domain terms, build a glossary, harden terminology, create a ubiquitous language, or mentions "domain model" or "DDD".
disable-model-invocation: true
---

## Ubiquitous Language

Extract and formalize domain terminology from the current conversation into a consistent glossary, saved to a local file.

### Process

1. **Scan the conversation** for domain-relevant nouns, verbs, and concepts
2. **Identify problems**:
   - Same word used for different concepts (ambiguity)
   - Different words used for the same concept (synonyms)
   - Vague or overloaded terms
3. **Propose a canonical glossary** with opinionated term choices
4. **Write to `UBIQUITOUS_LANGUAGE.md`** in the working directory using the format below
5. **Output a summary** inline in the conversation

### Output Format

Write a `UBIQUITOUS_LANGUAGE.md` file with this structure:

# Ubiquitous Language

## Order lifecycle

| Term        | Definition                                              | Aliases to avoid      |
| ----------- | ------------------------------------------------------- | --------------------- |
| **Order**   | A customer's request to purchase one or more items      | Purchase, transaction |
| **Invoice** | A request for payment sent to a customer after delivery | Bill, payment request |

## People

| Term         | Definition                                  | Aliases to avoid       |
| ------------ | ------------------------------------------- | ---------------------- |
| **Customer** | A person or organization that places orders | Client, buyer, account |
| **User**     | An authentication identity in the system    | Login, account         |

## Relationships

- An **Invoice** belongs to exactly one **Customer**
- An **Order** produces one or more **Invoices**

## Example dialogue

> **Dev:** "When a **Customer** places an **Order**, do we create the **Invoice** immediately?"
> **Domain expert:** "No — an **Invoice** is only generated once a **Fulfillment** is confirmed. A single **Order** can produce multiple **Invoices** if items ship in separate **Shipments**."
> **Dev:** "So if a **Shipment** is cancelled before dispatch, no **Invoice** exists for it?"
> **Domain expert:** "Exactly. The **Invoice** lifecycle is tied to the **Fulfillment**, not the **Order**."

## Flagged ambiguities

- "account" was used to mean both **Customer** and **User** — these are distinct concepts: a **Customer** places orders, while a **User** is an authentication identity that may or may not represent a **Customer**.

### Rules

- **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others as aliases to avoid.
- **Flag conflicts explicitly.** If a term is used ambiguously in the conversation, call it out in the "Flagged ambiguities" section with a clear recommendation.
- **Only include terms relevant for domain experts.** Skip the names of modules or classes unless they have meaning in the domain language.
- **Keep definitions tight.** One sentence max. Define what it IS, not what it does.
- **Show relationships.** Use bold term names and express cardinality where obvious.
- **Only include domain terms.** Skip generic programming concepts (array, function, endpoint) unless they have domain-specific meaning.
- **Group terms into multiple tables** when natural clusters emerge (e.g. by subdomain, lifecycle, or actor). Each group gets its own heading and table. If all terms belong to a single cohesive domain, one table is fine — don't force groupings.
- **Write an example dialogue.** A short conversation (3-5 exchanges) between a dev and a domain expert that demonstrates how the terms interact naturally. The dialogue should clarify boundaries between related concepts and show terms being used precisely.

## Re-running

When invoked again in the same conversation:

1. Read the existing `UBIQUITOUS_LANGUAGE.md`
2. Incorporate any new terms from subsequent discussion
3. Update definitions if understanding has evolved
4. Re-flag any new ambiguities
5. Rewrite the example dialogue to incorporate new terms
```

### Skill #3 — `tdd/SKILL.md` (verbatim, key sections)

```markdown
# Test-Driven Development

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification - "user can checkout with valid cart" tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (like querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and tests fail, those tests were testing implementation, not behavior.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing" - treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:
- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes - they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle. Because you just wrote the code, you know exactly what behavior matters and how to verify it.

WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...

## Workflow

### 1. Planning
- Confirm with user what interface changes are needed
- Confirm with user which behaviors to test (prioritize)
- Identify opportunities for deep modules (small interface, deep implementation)
- Design interfaces for testability
- List the behaviors to test (not implementation steps)
- Get user approval on the plan

Ask: "What should the public interface look like? Which behaviors are most important to test?"

**You can't test everything.** Confirm with the user exactly which behaviors matter most. Focus testing effort on critical paths and complex logic, not every possible edge case.

### 2. Tracer Bullet
Write ONE test that confirms ONE thing about the system.

### 3. Incremental Loop
For each remaining behavior:
- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior

### 4. Refactor
After all tests pass, look for refactor candidates. Never refactor while RED. Get to GREEN first.

## Checklist Per Cycle

- Test describes behavior, not implementation
- Test uses public interface only
- Test would survive internal refactor
- Code is minimal for this test
- No speculative features added
```

### Skill #4 — `triage-issue/SKILL.md` (paraphrased — WebFetch returned summary)

5-step process:
1. **Problem Capture** — gather a brief issue description with minimal questioning.
2. **Deep Investigation** — use exploration tools to identify where the bug manifests, what code path is involved, why it fails, and related patterns.
3. **Fix Approach** — determine the minimal change needed, affected modules, required test behaviors, and categorize the issue type.
4. **TDD Design** — create ordered RED-GREEN cycles where each represents one vertical slice. *"Tests verify behavior through public interfaces, not implementation details."*
5. **Issue Creation** — use `gh issue create` to submit, without requesting user review first.

Key principles: durability (avoiding implementation-specific details so issues stay relevant after refactors); behavior + contract focus, not internal structure; observable outcomes (API responses, UI state, user-visible effects), not internal state; minimal incremental changes verified through tests; refactoring reserved for final cleanup.

### Skill #5 — `request-refactor-plan/SKILL.md` (verbatim)

```markdown
---
name: request-refactor-plan
description: Create a detailed refactor plan with tiny commits via user interview, then file it as a GitHub issue. Use when user wants to plan a refactor, create a refactoring RFC, or break a refactor into safe incremental steps.
---

This skill will be invoked when the user wants to create a refactor request. You should go through the steps below. You may skip steps if you don't consider them necessary.

1. Ask the user for a long, detailed description of the problem they want to solve and any potential ideas for solutions.

2. Explore the repo to verify their assertions and understand the current state of the codebase.

3. Ask whether they have considered other options, and present other options to them.

4. Interview the user about the implementation. Be extremely detailed and thorough.

5. Hammer out the exact scope of the implementation. Work out what you plan to change and what you plan not to change.

6. Look in the codebase to check for test coverage of this area of the codebase. If there is insufficient test coverage, ask the user what their plans for testing are.

7. Break the implementation into a plan of tiny commits. Remember Martin Fowler's advice to "make each refactoring step as small as possible, so that you can always see the program working."

8. Create a GitHub issue with the refactor plan. Use the following template for the issue description:

<refactor-plan-template>

## Problem Statement

The problem that the developer is facing, from the developer's perspective.

## Solution

The solution to the problem, from the developer's perspective.

## Commits

A LONG, detailed implementation plan. Write the plan in plain English, breaking down the implementation into the tiniest commits possible. Each commit should leave the codebase in a working state.

## Decision Document

A list of implementation decisions that were made. This can include:
- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

## Testing Decisions

A list of testing decisions that were made. Include:
- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this refactor.

## Further Notes (optional)

Any further notes about the refactor.

</refactor-plan-template>
```

### Skill #6 — `improve-codebase-architecture/SKILL.md` (NOT FETCHED VERBATIM)

`WebFetch` declined to return verbatim content on the first attempt (model declined due to a quote-limit conflict). Description from repo index: *"Find architectural improvement opportunities informed by domain language."*

To re-fetch later, use `WebFetch` against `https://raw.githubusercontent.com/mattpocock/skills/main/improve-codebase-architecture/SKILL.md` with a less restrictive prompt.

---

## 3. `aihero.dev` site summary

**URL:** `https://aihero.dev`
**Tagline:** *"Your Job as a Developer is Changing Faster than You Can Imagine."*
**Audience size:** *"Join over 54,000 Developers Becoming AI Heroes"* (newsletter signup form)
**Positioning:** *"Keeping up with AI is a full-time job. I'll keep out the crap, and give you only the good stuff."*
**Featured product (at fetch time):** *"New: AI SDK v6 Crash Course"*
**Sections:** Learn / Live content areas, Browse all posts archive, Workshop offerings.
**About the creator:** Creator of Total TypeScript, former XState core team member, previous developer advocate at Vercel. Testimonial from Vercel CEO Guillermo Rauch: *"one of the best developer educators in the world."*

---

## End of Phase 1 evidence file
