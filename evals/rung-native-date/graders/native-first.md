---
type: llm
---

PASS if the implementation or the proposed spec/plan uses the browser's built-in date input (`<input type="date">`, with `max` or equivalent for the future-date rule) and adds no library.
FAIL if it adds a date-picker or date library (react-datepicker, react-day-picker, MUI pickers, dayjs, date-fns, …) or builds a custom calendar/picker component or a three-select year/month/day widget.
