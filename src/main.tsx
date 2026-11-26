import { createRoot } from "react-dom/client";
import App from "./App";
import CupInvite from "./CupInvite";
import "./scorer.css";
import "./style.css";
createRoot(document.getElementById("root")!).render(window.location.pathname.startsWith("/cup/") ? <CupInvite /> : <App />);
