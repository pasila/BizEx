defmodule BizEx.Schedule do
  @moduledoc """
  BizEx Schedule module.
  """

  alias BizEx.Period  

  defstruct time_zone: "Etc/UTC", periods: [], holidays: []

  @type t :: %__MODULE__ {
    time_zone: Timex.Types.time_zone,
    periods: list(Period.t),
    holidays: list(Date.t)
  }

  # TODO: Re-implement.
  #def load_config() do
  #%Schedule{
  #time_zone: load_schedule_timezone(),
  #schedule: load_schedule(),
  #holidays: load_holidays()
  #}
  #end

  #defp load_schedule() do
  #Application.get_env(:bizex, :schedule, %{})
  #end

  #defp load_schedule_timezone() do
  #Application.get_env(:bizex, :schedule_timezone, "Etc/UTC")
  #end

  # defp load_holidays() do
  #Application.get_env(:bizex, :holidays, [])
  #end

  def default() do
    %__MODULE__{
      time_zone: "Europe/London", 
      periods: [
        %Period{start_at: ~T[09:00:00], end_at: ~T[12:30:00], weekday: 1},
        %Period{start_at: ~T[13:00:00], end_at: ~T[17:30:00], weekday: 1},
        %Period{start_at: ~T[09:00:00], end_at: ~T[17:30:00], weekday: 2},
        %Period{start_at: ~T[09:00:00], end_at: ~T[17:30:00], weekday: 3},
        %Period{start_at: ~T[09:00:00], end_at: ~T[17:30:00], weekday: 4},
        %Period{start_at: ~T[09:00:00], end_at: ~T[17:30:00], weekday: 5}
      ],
      holidays: [
        ~D[2017-12-25]
      ]
      # TODO add date specific override support
      # How do we feel about something like this?
      # overrides: %{
      #   '2017-09-01': %Period{start_at: ~T[09:00:00], end_at: ~T[17:30:00]}
      # }
    }
  end

  @doc """
  Set the timezone of the schedule.
  """
  @spec set_timezone(t, Timex.Types.time_zone) :: t
  def set_timezone(%__MODULE__{} = schedule, time_zone) when is_binary(time_zone) do
    if Timex.Timezone.exists?(time_zone) do
      %{schedule | time_zone: time_zone}
    else 
      raise "invalid time zone"
    end
  end

  @doc """
  Add a working period (comprising of `start_at` time, `end_at` time and a `weekday` number) to a `schedule`, 
  ensuring that the periods are correctly ordered and no overlapping of periods occurs.
  """
  @spec add_period(t, Time.t, Time.t, Timex.Types.weekday | :mon | :tue | :wed | :thu | :fri | :sat | :sun) :: t
  def add_period(%__MODULE__{} = schedule, %Time{} = start_at, %Time{} = end_at, weekday) when is_number(weekday) and weekday >= 1 and weekday <= 7 do
    new_period = %Period{start_at: start_at, end_at: end_at, weekday: weekday}

    if overlaps?(schedule.periods, new_period) do
      raise "overlapping period defined, this is unsupported"      
    else    
      %{schedule | periods: sort_periods(schedule.periods ++ [new_period])}
    end
  end

  def add_period(%__MODULE__{} = schedule, %Time{} = start_at, %Time{} = end_at, weekday) when is_atom(weekday) do
    weekday_number = case weekday do
      :mon -> 1
      :tue -> 2
      :wed -> 3
      :thu -> 4
      :fri -> 5
      :sat -> 6
      :sun -> 7
    end

    add_period(schedule, start_at, end_at, weekday_number)
  end

  @doc """
  Add a holiday `date` to a `schedule`
  """
  @spec add_holiday(t, Date.t) :: t
  def add_holiday(%__MODULE__{} = schedule, %Date{} = date) do
    %{schedule | holidays: (schedule.holidays ++ [date])}
  end

  @doc """
  Checks if a given `date` is defined as a holiday, in the provided `schedule`
  """
  @spec holiday?(t, Date.t | DateTime.t | NaiveDateTime.t) :: boolean
  def holiday?(schedule, date)

  def holiday?(%__MODULE__{} = schedule, %Date{} = date) do
    Enum.member?(schedule.holidays, date)
  end

  def holiday?(%__MODULE__{} = schedule, %DateTime{} = datetime) do
    holiday?(schedule, DateTime.to_date(datetime))
  end

  def holiday?(%__MODULE__{} = schedule, %NaiveDateTime{} = datetime) do
    holiday?(schedule, NaiveDateTime.to_date(datetime))
  end

  @doc """
  Checks if a given `datetime` is between any of the provided `schedule` periods.

  Assumption is currently made that the timezone of the provided `datetime` is the same
  as the `schedule` timezone.
  """
  @spec between?(t, DateTime.t) :: {:ok, Period.t} | {:error, term()}
  def between?(%__MODULE__{} = schedule, %DateTime{} = datetime) do
    period = schedule.periods
             |> Enum.map(fn x ->
               if Period.between?(x, datetime) do
                 x
               end
             end)
             |> Enum.reject(&is_nil/1)
             |> List.first

    if !is_nil(period) and !holiday?(schedule, datetime) do
      {:ok, period}
    else
      {:error, "not in hours"}
    end
  end

  @doc """
  Fetch the any active period, for a given `datetime`, from the provided `schedule`.

  Assumption is currently made that the timezone of the provided `datetime` is the same
  as the `schedule` timezone.
  """
  @spec current(t, DateTime.t) :: {:ok, Period.t} | {:error, term()}
  def current(%__MODULE__{} = schedule, %DateTime{} = datetime) do
    between?(schedule, datetime)
  end

  @doc """
  Fetch the next active period, for a given `datetime`, from the provided `schedule`.

  Assumption is currently made that the timezone of the provided `datetime` is the same
  as the `schedule` timezone.
  """
  @spec next(t, DateTime.t, list) :: {:ok, Period.t, DateTime.t}
  def next(%__MODULE__{} = schedule, %DateTime{} = datetime, opts \\ []) do
    force_time = Keyword.get(opts, :force, false)

    period = schedule.periods
             |> Enum.map(fn x ->

               cond do
                 holiday?(schedule, datetime) ->
                   nil
                 force_time == true and Period.today?(x, datetime) ->
                   x
                 Period.after?(x, datetime) ->
                   x
                 true ->
                   nil
               end
             end)
             |> Enum.reject(&is_nil/1)
             |> List.first

    if is_nil(period) do
      next(schedule, Timex.shift(datetime, days: 1), [force: true])  
    else
      {:ok, period, Period.use_time(period, datetime, :start)}      
    end
  end

  @doc """
  Fetch the previous active period, for a given `datetime`, from the provided `schedule`.

  Assumption is currently made that the timezone of the provided `datetime` is the same
  as the `schedule` timezone.
  """
  @spec prev(t, DateTime.t, list) :: {:ok, Period.t, DateTime.t}
  def prev(%__MODULE__{} = schedule, %DateTime{} = datetime, opts \\ []) do
    force_time = Keyword.get(opts, :force, false)

    period = schedule.periods
             |> Enum.map(fn x ->

               cond do
                 holiday?(schedule, datetime) ->
                   nil
                 force_time == true and Period.today?(x, datetime) ->
                   x
                 Period.before?(x, datetime) ->
                   x
                 true ->
                   nil
               end
             end)
             |> Enum.reject(&is_nil/1)
             |> List.first

    if is_nil(period) do
      prev(schedule, Timex.shift(datetime, days: -1), [force: true])  
    else
      {:ok, period, Period.use_time(period, datetime, :end)}      
    end
  end

  # Sort a list of periods, into their correct order
  defp sort_periods(periods) do
    periods
    |> Enum.sort(fn x, y -> 
       # TODO this seems a bit crap, there's probably a better way to do it.
       if x.weekday == y.weekday do
         x.start_at < y.start_at
       else
         x.weekday < y.weekday
       end
     end)
  end

  # Determine if the new_period overlaps with any of the existing periods
  defp overlaps?(existing_periods, %Period{} = new_period) do
    Enum.any?(existing_periods, fn x -> 
        x.weekday == new_period.weekday and new_period.start_at >= x.start_at and new_period.start_at <= x.end_at
    end)
  end
end

