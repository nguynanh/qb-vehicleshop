import React from "react";
import { FaCompass } from "react-icons/fa";
import { twMerge } from "tailwind-merge";

interface IconLabelBoxProps extends React.HTMLAttributes<HTMLDivElement> {
  Icon?: React.ComponentType<{ className?: string }>;
  label?: string;
  className?: string;
  textClassName?: string;
  iconClassName?: string;
}

const IconLabelBox: React.FC<IconLabelBoxProps> = ({ Icon: Icon = FaCompass, label = "NW", className = "", textClassName = "", iconClassName = "", ...props }) => {
  return (
    <div className={twMerge(`flex items-center h-[2.5dvh] justify-center text-y_white bg-black/30 rounded-[8px] p-[1px] min-w-[5dvw]`, className)} {...props}>
      <Icon className={twMerge("mr-2 drop-shadow-[0_1.2px_1.2px_rgba(0,0,0,1)] text-[0.8vw]", iconClassName)} />
      <p
        className={twMerge(`text-center text-y_white font-bold text-[0.7vw] drop-shadow-[0_1.2px_1.2px_rgba(0,0,0,1)]`, textClassName)}
        style={{
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis",
        }}
      >
        {label}
      </p>
    </div>
  );
};

export default IconLabelBox;
