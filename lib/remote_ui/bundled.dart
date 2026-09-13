// Generated from server/internal/cortex/ui/release.json. No personal data.
const bundledLayoutJSON = r'''
{
  "schema": 1,
  "revision": "2026-09-13.2",
  "pages": {
    "space": {
      "type": "list",
      "padding": 22,
      "children": [
        {
          "type": "text",
          "text": "My space",
          "size": 26
        },
        {
          "type": "gap",
          "height": 8
        },
        {
          "type": "text",
          "text": "See where you are. Let\u2019s take it one step at a time.",
          "size": 14
        },
        {
          "type": "gap",
          "height": 28
        },
        {
          "type": "grid",
          "columns": 2,
          "ratio": 0.69,
          "gap": 14,
          "children": [
            {
              "type": "slot",
              "name": "time"
            },
            {
              "type": "slot",
              "name": "fitness"
            },
            {
              "type": "slot",
              "name": "money"
            },
            {
              "type": "slot",
              "name": "targets"
            }
          ]
        },
        {
          "type": "gap",
          "height": 26
        },
        {
          "type": "surface",
          "tone": "soft",
          "padding": 18,
          "radius": 22,
          "children": [
            {
              "type": "text",
              "text": "Tell Cortex what changed. Your chat updates these records, so you don\u2019t have to manage lots of forms.",
              "size": 14
            }
          ]
        }
      ]
    },
    "fitness": {
      "type": "list",
      "padding": 22,
      "children": [
        {
          "type": "slot",
          "name": "intro"
        },
        {
          "type": "slot",
          "name": "goal"
        },
        {
          "type": "slot",
          "name": "energy"
        },
        {
          "type": "slot",
          "name": "foodPhoto"
        },
        {
          "type": "slot",
          "name": "meals"
        },
        {
          "type": "slot",
          "name": "checkIn"
        },
        {
          "type": "slot",
          "name": "movement"
        },
        {
          "type": "slot",
          "name": "health"
        },
        {
          "type": "slot",
          "name": "readings"
        },
        {
          "type": "slot",
          "name": "chat"
        }
      ]
    },
    "time": {
      "type": "list",
      "padding": 22,
      "children": [
        {
          "type": "slot",
          "name": "intro"
        },
        {
          "type": "slot",
          "name": "todos"
        },
        {
          "type": "slot",
          "name": "plan"
        },
        {
          "type": "slot",
          "name": "routines"
        },
        {
          "type": "slot",
          "name": "calendars"
        },
        {
          "type": "slot",
          "name": "chat"
        }
      ]
    },
    "chat": {
      "type": "column",
      "children": [
        {
          "type": "slot",
          "name": "divider"
        },
        {
          "type": "slot",
          "name": "login"
        },
        {
          "type": "slot",
          "name": "conversation"
        },
        {
          "type": "slot",
          "name": "error"
        },
        {
          "type": "slot",
          "name": "composer"
        }
      ]
    },
    "composer": {
      "type": "column",
      "children": [
        {
          "type": "slot",
          "name": "images"
        },
        {
          "type": "slot",
          "name": "input"
        },
        {
          "type": "slot",
          "name": "actions"
        }
      ]
    },
    "userMessage": {
      "type": "bubble",
      "align": "right",
      "width": 0.85,
      "radius": 20,
      "padding": 16,
      "tone": "soft",
      "children": [
        {
          "type": "slot",
          "name": "content"
        }
      ]
    },
    "assistantMessage": {
      "type": "bubble",
      "align": "left",
      "width": 0.85,
      "radius": 20,
      "padding": 16,
      "tone": "white",
      "children": [
        {
          "type": "slot",
          "name": "content"
        }
      ]
    }
  }
}
''';
