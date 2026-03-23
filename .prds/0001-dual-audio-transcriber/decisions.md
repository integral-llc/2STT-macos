# PRD-0001: DualAudioTranscriber - Decision Log

Running log of decisions, scope changes, and clarifications made after the PRD was created.

| Date       | Decision                                                        | Context / Reason                                                                 |
|------------|-----------------------------------------------------------------|----------------------------------------------------------------------------------|
| 2026-03-23 | Initial PRD created                                             | -                                                                                |
| 2026-03-23 | LLM integration deferred to future version                      | V1 focuses on accurate real-time transcription; "copy all" is the LLM handoff    |
| 2026-03-23 | Xcode project chosen over SwiftPM CLI                           | Developer preference                                                             |
| 2026-03-23 | SRT export as single file with embedded speaker tags             | Simpler than separate tracks; ME/THEM tagging in text lines                      |
| 2026-03-23 | Tech spec treated as guidance, not prescriptive                  | Implementation may diverge from code samples as long as constraints are respected |
| 2026-03-23 | Zero buffering policy established                                | User must see words immediately; copy-all must capture latest volatile text       |
| 2026-03-23 | Manual testing for hardware integration                          | Audio capture and speech APIs require real hardware; unit tests cover data layer  |
