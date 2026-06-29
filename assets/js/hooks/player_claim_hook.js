import {writePlayerClaim} from "../player_claims";

const PlayerClaimHook = {
  mounted() {
    this.writeClaim();
  },
  updated() {
    this.writeClaim();
  },
  writeClaim() {
    writePlayerClaim({
      gameId: this.el.dataset.gameId,
      playerId: this.el.dataset.playerId,
      playerName: this.el.dataset.playerName,
      playerColor: this.el.dataset.playerColor,
    });
  },
};

export default PlayerClaimHook;
