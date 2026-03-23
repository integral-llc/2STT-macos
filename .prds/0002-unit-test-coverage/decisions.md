# PRD-0002: Extract DualSTT Library and Unit Test Coverage - Decision Log

Running log of decisions, scope changes, and clarifications made after the PRD was created.

| Date       | Decision                            | Context / Reason         |
|------------|-------------------------------------|--------------------------|
| 2026-03-23 | Initial PRD created                 | -                        |
| 2026-03-23 | Package rename included in scope    | Tech note assumes DualSTT naming throughout; rename is prerequisite for test imports |
| 2026-03-23 | BufferConverter extraction included in scope | Conversion logic must be extracted from SpeechPipeline to be unit testable |
| 2026-03-23 | Tests must verify format-change mid-stream | Current code handles device switch (SpeechPipeline:103-107); tests should cover this |
| 2026-03-23 | No priority ordering among test files | All must be done; implementer chooses order |
| 2026-03-23 | PRD expanded to cover full SPM library extraction | Original PRD only captured unit test plan; tech note also specifies directory restructure, access control, exporter relocation, consumer integration, and versioning |
| 2026-03-23 | Exporters move to library (Option A) | PlainTextExporter and SRTExporter are small (52 lines total), generic, and any consumer would want export. Avoids complex separate test target. |
| 2026-03-23 | SpeechPipeline made public           | Flank needs flexibility to wire system audio to pipeline without full TranscriptionEngine; BufferConverter stays internal as implementation detail |
| 2026-03-23 | Logger subsystem changes to "com.eugenerat.DualSTT" | Separates library logs from app logs in Console.app |
| 2026-03-23 | Tag v1.0.0 after verification       | Enables Flank to pin to stable version via SPM |
