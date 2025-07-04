import { useMemo } from "preact/hooks";

interface TextProgressBarProps extends React.HTMLAttributes<HTMLDivElement> {
  value?: number;
  icon?: React.ReactNode;
  color?: string;
  iconSize?: string;
  iconSpacing?: string;
}

export const TextProgressBar = ({ value = 50, icon, color = "#06CE6B", iconSize = "1.2vw", iconSpacing = "12px", ...props }: TextProgressBarProps) => {
  const getColor = useMemo(() => {
    if (value <= 20) return "#FE2436";
    if (value <= 50) return "#FB8607";
    return color;
  }, [color, value]);

  return (
    <div className={"flex flex-col items-center justify-center w-[2.1dvw] h-[4dvh]"} {...props}>
      <div
        className="flex items-center justify-center text-[1vw]"
        style={{
          height: iconSpacing,
          fontSize: iconSize,
          marginBottom: iconSpacing,
          color: 'rgba(255, 255, 255, 0.87)',
        }}
      >
        {icon}
      </div>
      <div className={"relative w-[80%] bg-black/20 shadow h-[3.5px] 4k:h-[5px] 4k:mt-1 rounded-full drop-shadow-[0_1.2px_1.2px_rgba(0,0,0,1)]"}>
        <div
          className="absolute max-w-full transition-all rounded-full shadow left-0 h-full z-20"
          style={{
            width: `${value}%`,
            backgroundColor: getColor,
          }}
        ></div>
      </div>
    </div>
  );
};
