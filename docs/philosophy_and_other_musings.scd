gluumy-philosophy(7) "gluumy" "gluumy programming language :: miscellanea"

# FOREWORD, or really, foreparagraph

This man page serves as the backing lore to the gluumy universe, or at least as
much of it as I've bothered to document so far. Eventually, it's possible that I
won't be the sole designer and otherwise-BDFL of this language, so eventually,
this document may have multiple contributors with multiple viewpoints on what
gluumy is and/or should be. Until then, consider this a technical diary of
sorts; a blog post written for a medium (roff-based man pages) that long
predates my own existence on this earth, other than by whatever carbon I was
formed from, and to that end, a love letter to composable, understandable,
resource-unintensive software *for humans*.

# DUDE, WHY?

This sentence of this paragraph of this document is being written in the year
2022. For those of you who weren't alive for it yet, congratulations, you dodged
a mess. Don't worry, the prior couple of years were also pretty rough, but we're
learning to make do. More to the point, however, in 2022 there's probably more
programming languages than there are stars in the Milky Way. We might be
approaching the point where there's more programming languages than there are
atoms in the galaxy, at which point some dude who does way too many shrooms will
probably come up with A Theory (TM) to describe this phenomenum, they'll hit the
front page of Reddit, and we'll all move on with our lives knowing _nobody needs
to be writing another programming language in 20-fucking-22._

You know what I did?

I wrote a programming language in 2022.

I'm not sorry.

Okay, maybe a little. But I digress.

gluumy was written to combine aspects I love from two vastly different flavors
of languages: one one end of the spectrum, highly sophisticated, strict,
type-safe languages like Rust and F# that have tons of features (and relatively
steep learning curves to match), and on the other end, relatively barebones and
hyper-flexible languages like Forth, where even comments are implemented as
"words" in the language in many cases, and all parts are relatively
interchangeable. What if type-safe languages had that sort of plug-and-play
interchangability? What if type-safe languages invited end-users to hack on the
internal bits of their applications (if they so desired), rather than hiding
those details, or practically hiding them by way of language complexity?

Further, I wanted a language (and surrounding ecosystem: there's certainly a
social - or perhaps anti-social, if this language ends up being solely for me,
which is also perfectly fine - aspect to software engineering) that was usable
in development scenarios (and even runtime scenarios) that aren't what we
commonly associate with dev scenarios: if I'm on my boat with a relatively (by
2020s standards) weak ARM laptop, many of those highly sophisticated languages
out there will be extremely painful to work with (compilation time and/or
battery drain will eventually become problematic).

Lastly, I wanted a language that encourages minimalism and, perhaps a bit
controversially (and even an adjustment from my own past stances on the matter),
deep understanding of one's dependencies. I won't dwell on this point here for
long - instead, I hope those goals shine through for themselves as you explore
the decisions made in gluumy's design process.
