torb - TOR to WWW
=================
The basic concept is that we need a way to make it easy to access hidden HTTP services,
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
`domainofpuppet/403926033d001b5279df37cbbe5287b7c7c267fa` and it will be used to contact the
**puppet master** and get the last visited page.

When the session is created it is linked to a single **puppet**, in this way cookie problems are avoided, this
also means that cookie aren't maintained through multiple sessions, for obvious reasons.

The **puppet** and the **puppet master** share a secret key that authorizes the **puppet** to fetch the data, each
**puppet** has a different key, so that revoking authorizations is easy.

Linking pages on hidden services
--------------------------------
Because of what said in the *Design* section linking to a page on torb isn't really easy, the solution is to have
a page where you can pass your session hash and get a page with an optional password and an expire time (with a
reasonable max time of life) so you can send links of hidden services for direct access.

If a password is given the max time of life is sensibly longer than the one without password, this is done to avoid
spam linking to hidden services and the like.

Client side security
--------------------
There *will* be multiple client side security modes (this needs a bit of serious research):

* Give it your PGP public key and get back PGP encrypted stuff (use FirePGP or something on those lines to decrypt)
* Give it a simple password and choose the algorithm and get back encrypted html pages that will get automagically
  decrypted on the client (allows to encrypt only html)

SSL certification
-----------------
Instead of using a shared certificate, I think the best way would be to host a [convergence](http://convergence.io/)
notary to make removal and addition of nodes easier.

Or let the puppets have their own certificate, I don't think having a shared certificate is a good idea.

I don't think having the nodes under the same domain and maintained by the same people is a good idea either.

The **master** will be managed by trusted people that will keep checking if the puppets are doing right and
will have the job of adding and removing puppets when needed, in this way everything will be really
decentralized, and decentralized is good.

How to run
----------
First of all make sure to have installed bundler (`gem install bundler` should suffice if your Ruby isn't fucked up).

Then just run `bundle install` inside *master* and *puppet*, this will install the needed dependencies.

At this point you can run the *master* by simply executing it inside its dir and the *puppet* by running
`thin start -R puppet.ru` inside its dir.

Status
------
The design should work with the target I have in mind, the code isn't still there completely but it's on the way.
