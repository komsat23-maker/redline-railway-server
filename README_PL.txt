REDLINE - Railway server (minimalny pakiet)

Pliki w tym folderze wrzucasz do osobnego repo na GitHub:
- project.godot
- dedicated_server.gd
- dedicated_server.tscn
- Dockerfile
- .dockerignore

Railway:
1) New Project -> Deploy from GitHub Repo (to repo z tym folderem)
2) W Variables dodaj:
   PORT=8080
3) W Settings -> Networking ustaw Service Port = 8080
4) Wygeneruj domenę

W grze (Join) wpisz:
wss://TWOJA-DOMENA.up.railway.app

Uwaga:
- Na Railway nie używaj Host w kliencie gry.
- Obie osoby robią Join na ten sam adres wss.
