import Contexir.Layer
require Contexir

# Declarative context modules keep selection logic out of the call site. The
# request data below is translated into a list of active layers, then dispatch
# uses those layers for the duration of the call.

defmodule Examples.DeclarativeContext.Report do
  use Contexir

  def build(report, _ctx) do
    report
  end
end

deflayer Examples.DeclarativeContext.InternalAudience do
  defpartial Examples.DeclarativeContext.Report.build(report, _ctx), mode: :around do
    continue(
      Examples.DeclarativeContext.Report,
      :build,
      [%{report | sections: report.sections ++ [:margin_notes]}]
    )
  end
end

deflayer Examples.DeclarativeContext.ExecutiveSummary do
  defpartial Examples.DeclarativeContext.Report.build(report, _ctx), mode: :around do
    continue(
      Examples.DeclarativeContext.Report,
      :build,
      [%{report | sections: [:summary | report.sections]}]
    )
  end
end

defcontext Examples.DeclarativeContext.ReportContext do
  layer(Examples.DeclarativeContext.InternalAudience, when: &(&1.audience == :internal))
  layer(Examples.DeclarativeContext.ExecutiveSummary, when: &(&1.role in [:director, :vp]))
end

report =
  Contexir.with_context(
    Examples.DeclarativeContext.ReportContext,
    %{audience: :internal, role: :vp},
    Examples.DeclarativeContext.Report.build(%{sections: [:metrics, :risks]}, %{})
  )

IO.inspect(report, label: "internal executive report")

report =
  Contexir.with_context(
    Examples.DeclarativeContext.ReportContext,
    %{audience: :partner, role: :vp},
    Examples.DeclarativeContext.Report.build(%{sections: [:metrics, :risks]}, %{})
  )

IO.inspect(report, label: "partner executive report")

report =
  Contexir.with_context(
    Examples.DeclarativeContext.ReportContext,
    %{audience: :internal, role: :analyst},
    Examples.DeclarativeContext.Report.build(%{sections: [:metrics, :risks]}, %{})
  )

IO.inspect(report, label: "internal analyst report")
