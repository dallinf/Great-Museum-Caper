import {applyRejoinLinks} from "../player_claims";

const LobbyRejoinHook = {
  mounted() {
    this.applyRejoinLinks();
  },
  updated() {
    this.applyRejoinLinks();
  },
  applyRejoinLinks() {
    applyRejoinLinks(this.el);
  },
};

export default LobbyRejoinHook;
