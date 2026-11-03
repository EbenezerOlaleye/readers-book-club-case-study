// Excerpt from the private Readers Book Club repository (apps/backend/src/auth/auth.service.ts).
// Refresh token rotation: one atomic findOneAndUpdate, so parallel refreshes can't each issue a token.

  /** Swaps a refresh token for a new access token and a new refresh token. */
  async refresh(refreshToken: string | undefined): Promise<AuthResult> {
    const [sessionId, secret] = (refreshToken ?? '').split('.');
    if (!sessionId || !secret || !isValidObjectId(sessionId)) {
      throw new UnauthorizedException(INVALID_SESSION);
    }

    const presented = sha256(secret);
    const newSecret = randomBytes(32).toString('base64url');
    const now = new Date();

    // One atomic read-and-write: of several requests presenting the same
    // token at once, exactly one matches and rotates it. A separate read then
    // save would let each of them issue its own token, all but one unusable.
    const session = await this.sessions
      .findOneAndUpdate(
        { _id: sessionId, tokenHash: presented, expiresAt: { $gt: now } },
        {
          $set: {
            previousTokenHash: presented,
            rotatedAt: now,
            tokenHash: sha256(newSecret),
            expiresAt: new Date(
              now.getTime() + REFRESH_TOKEN_TTL_SECONDS * 1000,
            ),
          },
        },
        { new: true },
      )
      .exec();

    if (!session) {
      await this.rejectStaleToken(sessionId, presented);
      throw new UnauthorizedException(INVALID_SESSION);
    }

    const user = await this.users.findById(session.userId.toString());
    if (!user) {
      await session.deleteOne();
      throw new UnauthorizedException(INVALID_SESSION);
    }

    return {
      user: toPublicUser(user),
      accessToken: await this.signAccessToken(user),
      refreshToken: `${session.id as string}.${newSecret}`,
    };
  }
