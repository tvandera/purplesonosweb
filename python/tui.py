from textual.logging import TextualHandler
from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical
from textual.widgets import Button, Input, Static, ListView, ListItem, Label, Header, Footer
from textual.reactive import reactive
import httpx

import logging
logging.basicConfig(level="NOTSET", handlers=[TextualHandler()])


API_BASE = "http://localhost:9999/api"

class MusicCLIApp(App):
    CSS_PATH = None

    search_term = reactive("")

    def compose(self) -> ComposeResult:
        yield Header()
        yield Vertical(
            Horizontal(
                Input(placeholder="Search for music...", id="search_box"),
                Button("Search", id="search_button"),
                id="search_row"
            ),
            Horizontal(
                Vertical(
                    Label("Zones"),
                    ListView(id="zones"),
                ),
                Vertical(
                    Label("Queue"),
                    ListView(id="queue"),
                ),
            ),
            Horizontal(
                Vertical(
                    Label("Controls"),
                    Horizontal(
                        Button("▶", id="play"),
                        Button("⏸", id="pause"),
                        Button("⏹", id="stop"),
                        Button("🔇", id="mute"),
                        id="control_row1"
                    ),
                    Horizontal(
                        Button("🔊+", id="vol_up"),
                        Button("🔉-", id="vol_down"),
                        id="control_row2"
                    ),
                ),
                Vertical(
                    Label("Search Results"),
                    ListView(id="results"),
                )
            )
        )
        yield Footer()

    async def on_mount(self) -> None:
        logging.info("Starting up...")
        await self.load_zones()

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        button_id = event.button.id
        if button_id == "search_button":
            self.search_term = self.query_one("#search_box", Input).value
            self.do_search(self.search_term)
        else:
            self.perform_action(button_id)

    async def load_zones(self):
        async with httpx.AsyncClient() as client:
            resp = await client.get(API_BASE, params={"what": "zones"})
            zones = self.query_one("#zones", ListView)
            zones.clear()
            for z in resp.json().keys():
                zones.append(ListItem(Label(z)))

    async def do_search(self, term: str):
        async with httpx.AsyncClient() as client:
            resp = await client.get(API_BASE, params={"what": "music", "search": term})
            results = resp.json()
            results_panel = self.query_one("#results", ListView)
            results_panel.clear()
            for r in results:
                label = r.get("title") or str(r)
                results_panel.append(ListItem(Label(label)))

    async def perform_action(self, action: str):
        action_map = {
            "play": "play",
            "pause": "pause",
            "stop": "stop",
            "mute": "mute",
            "vol_up": "volume+",
            "vol_down": "volume-"
        }
        act = action_map.get(action, action)
        try:
            with httpx.AsyncClient() as client:
                await client.get(API_BASE, params={"action": act})
                self.query_one("#results", ListView).append(ListItem(Label(f"Action: {act}")))
        except Exception as e:
            self.query_one("#results", ListView).append(ListItem(Label(f"Action error: {e}")))



    BINDINGS = [
        ("d", "toggle_dark", "Toggle dark mode"),
    ]



if __name__ == "__main__":
    app = MusicCLIApp()
    app.run()

