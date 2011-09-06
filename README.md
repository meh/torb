torb - TOR to WWW
=================
The basic concept is that we need a secure way to make it easy to access hidden HTTP services,
and make it hard to shutdown the whole torb thing because of serving illegal content and the like.

Design
------
The **puppet** is a simple forwarder that forwards the request through TOR to the wanted hidden service.

The **puppet master** is a redirector and a database, its purpose is to redirect the user to the proper
**puppet** and it will fetch the request made to its master to forward it through TOR and return the response
properly.

When an user tries to go to torb and hasn't got a session a session creation page is showed to him with a certain
number of settable options and a hash is generated for him, this hash is saved in the database and is used to
refer to said session. This means that the only URL that will be seen is something on the lines of
`nameofhiddenservice.domainofpuppet/403926033d001b5279df37cbbe5287b7c7c267fa` and it will be used to contact the
**puppet master** and get the last visited page.

When the session is created it is linked to a single **puppet**, in this way cookie problems are avoided, this
also means that cookie aren't maintained through multiple sessions, for obvious reasons.

The **puppet** and the **puppet master** share a secret key that authorizes the **puppet** to fetch the data, each
**puppet** has a different key, so that revoking authorizations is made easy.

Possible privacy problems
-------------------------
The last visited page is saved in the database (and **ONLY**) the last page, it is retained for a settable max time
or until fetched by the **puppet** (this is the adviced mode). Saving the last visited page is needed because torb
needs to know it for a **puppet** to fetch the right page. It's also used to make linking possible (if wanted).

The database data is **NOT** linked to any IP or anything linkable to the entity, the data is only linked to a
per session/time hash and is cleaned as soon as possible, if you want you can do a "log out" and be sure that all the
data is deleted at that time.

Linking pages on hidden services
--------------------------------
Because of what said in the *Design* section linking to a page on torb isn't really easy, the solution is to have
a page where you can pass your session hash and get a page with an optional password and an expire time (with a
reasonable max time of life) so you can send links of hidden services for direct access.

If a password is given the max time of life is sensibly longer than the one without password, this is done to avoid
spam linking to hidden services and the like.

Client side security
--------------------
There will be multiple client side security modes (this needs a bit of serious research):
* Give it your PGP public key and get back PGP encrypted stuff (use FirePGP or something on those lines to decrypt)
* Give it a simple password and choose the algorithm and get back encrypted html pages that will get automagically
  decrypted on the client (allows to encrypt only html)

Status
------
The design should work with the target I have in mind, the code isn't still there completely but it's on its way.
