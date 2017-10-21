!
! This file is part of libdcdfort
! https://github.com/wesbarnett/dcdfort
!
! Copyright (c) 2017 by James W. Barnett
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

!> @file
!> @author James W. Barnett, Columbia University
!
!> @brief Module that contains dcdreader class

module dcdfort_reader

    use dcdfort_common
    use iso_c_binding, only: C_NULL_CHAR

    implicit none

    real(8), parameter :: pi = 2.0d0*dacos(0.0d0)

    !> @brief dcdwriter class
    type, public :: dcdfile
        integer, private :: u
        integer(8), private :: filesize
    contains
        !> Opens file to read from
        procedure :: open => dcdfile_open
        !> Reads header of open DCD file
        procedure :: read_header => dcdfile_read_header
        !> Closes DCD file
        procedure :: close => dcdfile_close
        !> Reads next frame into memory
        procedure :: read_next => dcdfile_read_next
        !> Skips reading this frame into memory
        procedure :: skip_next => dcdfile_skip_next
    end type dcdfile

contains

    !> @brief Opens file to read from
    !> @param[inout] this dcdreader object
    !> @param[in] filename name of of DCD file to read from
    subroutine dcdfile_open(this, filename)

        implicit none
        character (len=*), parameter :: magic_string = "CORD"
        integer, parameter :: magic_number = 84
        character (len=*), intent(in) :: filename
        class(dcdfile), intent(inout) :: this
        integer :: line1
        character (len=4) :: line2
        logical :: ex
        character (len=256) :: endian

        inquire(file=trim(filename), exist=ex, size=this%filesize)

        if (ex .eqv. .false.) then
            call error_stop_program(trim(filename)//" does not exist.")
        end if

        open(newunit=this%u, file=trim(filename), form="unformatted", access="stream")
        inquire(this%u, convert=endian)

        read(this%u,pos=1) line1
        read(this%u) line2

        if (line1 .ne. magic_number .or. line2 .ne. magic_string) then

            ! Try converting to the reverse endianness
            close(this%u)
            open(newunit=this%u, file=trim(filename), form="unformatted", access="stream", convert="swap")
            inquire(this%u, convert=endian)

            read(this%u,pos=1) line2
            read(this%u) line2

            if (line1 .ne. magic_number .or. line2 .ne. magic_string) then
                call error_stop_program("This dcd file format is not supported, or the file header is corrupt.")
            end if

            write(error_unit, '(a)') prompt//"Detected opposite endianness ("//trim(endian)//")."

        else

            write(error_unit, '(a)') prompt//"Detected native endianness ("//trim(endian)//")."

        end if


    end subroutine dcdfile_open

    !> @brief Reads header of open DCD file
    !> @details Should be called after open()
    !> @param[inout] this dcdreader object
    !> @param[in] nframes rnumber of frames (snapshots) in file
    !> @param[out] istart first timestep of trajectory file
    !> @param[out] nevery how often (in timesteps) file was written to
    !> @param[out] iend last timestep of trajectory file
    !> @param[out] timestep timestep of simulation
    !> @param[out] natoms number of atoms in each snapshot
    subroutine dcdfile_read_header(this, nframes, istart, nevery, iend, timestep, natoms)

        implicit none

        integer :: dummy
        integer, intent(out) :: nframes, istart, nevery, iend, natoms
        integer :: i, ntitle, n, framesize, nframes2
        character (len=4) :: cord_string
        character (len=80) :: title_string
        real, intent(out) :: timestep
        class(dcdfile), intent(inout) :: this

        ! Already checked above
        read(this%u, pos=1) dummy
        read(this%u) cord_string

        ! Number of snapshots in file
        read(this%u) nframes

        ! Timestep of first snapshot
        read(this%u) istart

        ! Save snapshots every this many steps
        read(this%u) nevery

        ! Timestep of last snapshot
        read(this%u) iend

        do i = 1, 5
            read(this%u) dummy
        end do

        ! Simulation timestep
        read(this%u) timestep

        do i = 1, 12
            read(this%u) dummy
        end do

        read(this%u) ntitle
        if (ntitle > 0) then
            write(error_unit,'(a)') prompt//"The following titles were found:"
        end if
        do i = 1, ntitle
            read(this%u) title_string

            n = 1
            do while (n .le. 80 .and. title_string(n:n) .ne. C_NULL_CHAR)
                n = n + 1
            end do

            write(error_unit,'(a)') prompt//"  "//trim(title_string(1:n))
        end do

        read(this%u) dummy
        read(this%u) dummy
        if (dummy .ne. 4) then
            call error_stop_program("This dcd file format is not supported, or the file header is corrupt.")
        end if

        ! Number of atoms in each snapshot
        read(this%u) natoms

        read(this%u) dummy

        ! Each frame has natoms*3 (4 bytes each) = natoms*12
        ! plus 6 box dimensions (8 bytes each) = 48
        ! Additionally there are 32 bytes of file information in each frame
        framesize = natoms*12 + 80
        ! Header is 276 bytes
        nframes2 = (this%filesize-276)/framesize
        if ( nframes2 .ne. nframes) then
            write(error_unit,'(a,i0,a,i0,a)') prompt//"WARNING: Header indicates ", nframes, &
                &" frames, but file size indicates ", nframes2, "." 
            nframes = nframes2
        end if

    end subroutine dcdfile_read_header

    !> @brief Closes DCD file
    !> @param[inout] this dcdreader object
    subroutine dcdfile_close(this)

        implicit none
        class(dcdfile), intent(inout) :: this

        close(this%u)

    end subroutine dcdfile_close

    !> @brief Reads next frame into memory
    !> @param[inout] this dcdreader object
    !> @param[inout] xyz coordinates of all atoms in snapshot
    !> @param[inout] box dimensions of snapshot
    subroutine dcdfile_read_next(this, xyz, box)

        implicit none
        real, allocatable, intent(inout) :: xyz(:,:)
        real(8), intent(inout) :: box(6)
        integer :: dummy
        class(dcdfile), intent(inout) :: this
    
        ! Should be 48
        read(this%u) dummy

        read(this%u) box(1) ! A
        read(this%u) box(6) ! gamma
        read(this%u) box(2) ! B
        read(this%u) box(5) ! beta
        read(this%u) box(4) ! alpha
        read(this%u) box(3) ! C
        if (box(4) >= -1.0 .and. box(4) <= 1.0 .and. box(5) >= -1.0 .and. box(5) <= 1.0 .and. &
            box(6) >= -1.0 .and. box(6) <= 1.0) then
            box(4) = 90.0 - asin(box(4)) * 180.0 / pi
            box(5) = 90.0 - asin(box(5)) * 180.0 / pi
            box(6) = 90.0 - asin(box(6)) * 180.0 / pi
        end if

        ! 48 again
        read(this%u) dummy
        read(this%u) dummy

        read(this%u) xyz(1,:)

        ! 48 again
        read(this%u) dummy
        read(this%u) dummy

        read(this%u) xyz(2,:)

        ! 48 again
        read(this%u) dummy
        read(this%u) dummy

        read(this%u) xyz(3,:)

        read(this%u) dummy

    end subroutine dcdfile_read_next

    !> @brief Skips reading this frame into memory
    !> @param[inout] this dcdreader object
    subroutine dcdfile_skip_next(this)

        implicit none
        real :: real_dummy
        integer :: dummy, i
        real(8) :: box_dummy(6)
        class(dcdfile), intent(inout) :: this
    
        ! Should be 48
        read(this%u) dummy

        read(this%u) box_dummy

        ! 48 again
        read(this%u) dummy
        read(this%u) dummy

        do i = 1, dummy/4
            read(this%u) real_dummy
        end do

        ! 48 again
        read(this%u) dummy
        read(this%u) dummy

        do i = 1, dummy/4
            read(this%u) real_dummy
        end do

        ! 48 again
        read(this%u) dummy
        read(this%u) dummy

        do i = 1, dummy/4
            read(this%u) real_dummy
        end do

        read(this%u) dummy

    end subroutine dcdfile_skip_next

end module dcdfort_reader
