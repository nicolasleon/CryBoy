class Memory
  ROM_BANK_0    = 0x0000..0x3FFF
  ROM_BANK_N    = 0x4000..0x7FFF
  VRAM          = 0x8000..0x9FFF
  EXTERNAL_RAM  = 0xA000..0xBFFF
  WORK_RAM_0    = 0xC000..0xCFFF
  WORK_RAM_N    = 0xD000..0xDFFF
  ECHO          = 0xE000..0xFDFF
  SPRITE_TABLE  = 0xFE00..0xFE9F
  NOT_USABLE    = 0xFEA0..0xFEFF
  IO_PORTS      = 0xFF00..0xFF7F
  HRAM          = 0xFF80..0xFFFE
  INTERRUPT_REG = 0xFFFF

  @memory = Bytes.new 0xFFFF + 1
  @bootrom = Bytes.new 0

  def initialize(@cartridge : Cartridge, @interrupts : Interrupts, @ppu : PPU, @joypad : Joypad, @timer : Timer, bootrom : String? = nil)
    if !bootrom.nil?
      File.open bootrom do |file|
        raise "Bootrom too big: #{file.size}" if file.size > 256
        @bootrom = Bytes.new file.size
        file.read @bootrom
      end
    end
  end

  macro bit(name, location, mask)
    {{name.id.upcase}}_MASK = {{mask}}
    def {{name.id}}=(on : Int | Bool)
      if on == false || on == 0
        self[{{location}}] &= ~{{name.id.upcase}}_MASK
      else
        self[{{location}}] |= {{name.id.upcase}}_MASK
      end
    end
    def {{name.id}} : Bool
      self[{{location}}] & {{name.id.upcase}}_MASK == {{name.id.upcase}}_MASK
    end
  end

  bit vblank_interrupt, 0xFF0F, 0b00000001
  bit lcd_stat_interrupt, 0xFF0F, 0b00000010
  bit timer_interrupt, 0xFF0F, 0b00000100
  bit serial_interrupt, 0xFF0F, 0b00001000
  bit joypad_interrupt, 0xFF0F, 0b00010000

  bit vblank_enabled, 0xFFFF, 0b00000001
  bit lcd_stat_enabled, 0xFFFF, 0b00000010
  bit timer_enabled, 0xFFFF, 0b00000100
  bit serial_enabled, 0xFFFF, 0b00001000
  bit joypad_enabled, 0xFFFF, 0b00010000

  bit lcd_enabled, 0xFF40, 0b10000000
  bit window_tile_map, 0xFF40, 0b01000000
  bit window_enabled, 0xFF40, 0b00100000
  bit bg_window_tile_map, 0xFF40, 0b00010000
  bit bg_tile_map, 0xFF40, 0b00001000
  bit sprite_height, 0xFF40, 0b00000100
  bit sprite_enabled, 0xFF40, 0b00000010
  bit bg_display, 0xFF40, 0b00000001

  # read 8 bits from memory
  def [](index : Int) : UInt8
    case index
    when 0x0000...@bootrom.size then @bootrom.nil? ? @cartridge[index] : @bootrom[index]
    when ROM_BANK_0             then @cartridge[index]
    when ROM_BANK_N             then @cartridge[index]
    when VRAM                   then @ppu[index]
    when EXTERNAL_RAM           then @cartridge[index]
    when WORK_RAM_0             then @memory[index]
    when WORK_RAM_N             then @memory[index]
    when ECHO                   then @memory[index - 0x2000]
    when SPRITE_TABLE           then @ppu[index]
    when NOT_USABLE             then 0_u8
    when IO_PORTS
      case index
      when 0xFF00         then @joypad.read
      when 0xFF04..0xFF07 then @timer[index]
      when 0xFF0F         then @interrupts[index]
      when 0xFF10..0xFF3F then @memory[index]
      when 0xFF40..0xFF4B then @ppu[index]
      when 0xFF4F         then @ppu[index]
      when 0xFF51..0xFF55 then @ppu[index]
      else                     @memory[index]
      end
    when HRAM          then @memory[index]
    when INTERRUPT_REG then @interrupts[index]
    else                    raise "FAILED TO GET INDEX #{index}"
    end
  end

  # write 8 bits to memory
  def []=(index : Int, value : UInt8) : Nil
    @bootrom = Bytes.new 0 if index == 0xFF50 && value == 0x01
    # puts "writing at index #{hex_str index.to_u16!} : #{hex_str value}"
    # todo other dma stuff
    case index
    when ROM_BANK_0   then @cartridge[index] = value
    when ROM_BANK_N   then @cartridge[index] = value
    when VRAM         then @ppu[index] = value
    when EXTERNAL_RAM then @cartridge[index] = value
    when WORK_RAM_0   then @memory[index] = value
    when WORK_RAM_N   then @memory[index] = value
    when ECHO         then @memory[index - 0x2000] = value
    when SPRITE_TABLE then @ppu[index] = value
    when NOT_USABLE   then nil # todo: should I raise here?
    when IO_PORTS
      case index
      when 0xFF00         then @joypad.write value
      when 0xFF01         then @memory[index] = value # ; print value.chr
      when 0xFF04..0xFF07 then @timer[index] = value
      when 0xFF0F         then @interrupts[index] = value
      when 0xFF10..0xFF3F then @memory[index] = value
      when 0xFF40..0xFF4B then @ppu[index] = value
      when 0xFF4F         then @ppu[index] = value
      when 0xFF51..0xFF55 then @ppu[index] = value
      when 0xFF46         then dma_transfer(value.to_u16 << 8)
      else                     @memory[index] = value
      end
    when HRAM          then @memory[index] = value
    when INTERRUPT_REG then @interrupts[index] = value
    else                    raise "FAILED TO SET INDEX #{index}"
    end
  end

  # write 16 bits to memory
  def []=(index : Int, value : UInt16) : Nil
    self[index] = (value & 0xFF).to_u8
    self[index + 1] = (value >> 8).to_u8
  end

  # read 16 bits from memory
  def read_word(index : Int) : UInt16
    self[index].to_u16 | (self[index + 1].to_u16 << 8)
  end

  def dma_transfer(source : UInt16) : Nil
    # todo add delay
    (0x00..0x9F).each { |i| self[0xFE00 + i] = self[source + i] }
  end
end
