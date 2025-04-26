from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical
from textual.widgets import Button, Input, Static, ListView, ListItem, Label
from textual.reactive import reactive
import httpx


API_BASE = "http://localhost:9999/api"

class MusicCLIApp(App):
    CSS_PATH = None

    search_term = reactive("")

    def compose(self) -> ComposeResult:
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

    async def on_mount(self) -> None:
        await self.load_zones()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        button_id = event.button.id
        if button_id == "search_button":
            self.search_term = self.query_one("#search_box", Input).value
            self.call_from_worker(self.do_search, self.search_term)
        else:
            self.call_from_worker(self.perform_action, button_id)

    async def load_zones(self):
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(API_BASE, params={"what": "zone"})
                zones = resp.json()
                zone_list = self.query_one("#zones", ListView)
                zone_list.clear()
                for z in zones:
                    zone_list.append(ListItem(Label(z.get("name", "Unknown Zone"))))
        except Exception as e:
            self.query_one("#results", ListView).append(ListItem(Label(f"Error loading zones: {e}")))

    async def do_search(self, term: str):
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(API_BASE, params={"what": "music", "search": term})
                results = resp.json()
                results_panel = self.query_one("#results", ListView)
                results_panel.clear()
                for r in results:
                    label = r.get("title") or str(r)
                    results_panel.append(ListItem(Label(label)))
        except Exception as e:
            self.query_one("#results", ListView).append(ListItem(Label(f"Search error: {e}")))

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
            async with httpx.AsyncClient() as client:
                await client.get(API_BASE, params={"action": act})
                self.query_one("#results", ListView).append(ListItem(Label(f"Action: {act}")))
        except Exception as e:
            self.query_one("#results", ListView).append(ListItem(Label(f"Action error: {e}")))


if __name__ == "__main__":
    app = MusicCLIApp()
    app.run()

