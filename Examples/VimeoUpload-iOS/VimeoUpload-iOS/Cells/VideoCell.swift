//
//  VideoCell.swift
//  VimeoUpload
//
//  Created by Alfred Hanssen on 11/23/15.
//  Copyright © 2015 Vimeo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit
import VimeoNetworking
import VimeoUpload

protocol VideoCellDelegate: class
{
    func cellDidDeleteVideoWithUri(cell: VideoCell, videoUri: String)
}

class VideoCell: UITableViewCell
{
    // MARK:
    
    static let CellIdentifier = "VideoCellIdentifier"
    static let NibName = "VideoCell"
    
    // MARK:

    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var progressView: UIView!
    @IBOutlet weak var progressConstraint: NSLayoutConstraint!
    @IBOutlet weak var deleteButton: UIButton!
    
    // MARK:

    weak var delegate: VideoCellDelegate?

    // MARK: 
    
    fileprivate static let ProgressKeyPath = "progressObservable"
    fileprivate static let StateKeyPath = "stateObservable"
    fileprivate var progressKVOContext = UInt8()
    fileprivate var stateKVOContext = UInt8()
    
    fileprivate var observersAdded = false

    fileprivate var descriptor: UploadDescriptor?
    {
        willSet
        {
            self.removeObserversIfNecessary()
        }
        
        didSet
        {
            if let state = descriptor?.state
            {
                self.updateState(state)
            }
            
            self.addObserversIfNecessary()
        }
    }
    
    // MARK: 
    
    var video: VIMVideo?
    {
        didSet
        {
            if let video = self.video,
                let uri = video.uri
            {
                self.setupImageView(video: video)
                self.setupStatusLabel(video: video)
                self.descriptor = NewVimeoUploader.sharedInstance.descriptorForVideo(videoUri: uri)
            }
        }
    }
    
    // MARK: - Initialization

    deinit
    {
        self.removeObserversIfNecessary()
    }
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.updateState(.Finished)
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
    
        self.descriptor = nil
        self.video = nil
        self.thumbnailImageView?.image = nil
        self.statusLabel.text = ""
        self.errorLabel.text = ""

        self.updateState(.Finished)
    }
    
    // MARK: Actions
    
    @IBAction func didTapDeleteButton(_ sender: UIButton)
    {
        if let videoUri = self.video?.uri
        {
            self.descriptor = nil
            self.updateProgress(0)
            
            self.delegate?.cellDidDeleteVideoWithUri(cell: self, videoUri: videoUri)
        }
    }

    // MARK: Video Setup
    
    fileprivate func setupImageView(video: VIMVideo)
    {
        let width = Float(self.thumbnailImageView.frame.size.width * UIScreen.main.scale)
        if let picture = video.pictureCollection?.picture(forWidth: width), let link = picture.link, let url = URL(string: link)
        {
            self.thumbnailImageView.setImageWith(url)
        }
    }
    
    fileprivate func setupStatusLabel(video: VIMVideo)
    {
        self.statusLabel.text = video.status
    }

    // MARK: Descriptor Setup

    fileprivate func updateProgress(_ progress: Double)
    {
        let width = self.contentView.frame.size.width
        let constant = CGFloat(1 - progress) * width
        self.progressConstraint.constant = constant
    }

    fileprivate func updateState(_ state: DescriptorState)
    {
        switch state
        {
        case .Ready:
            self.updateProgress(0)
            self.progressView.isHidden = false
            self.deleteButton.setTitle("Cancel", for: UIControlState())
            self.errorLabel.text = "Ready"
            
        case .Executing:
            self.progressView.isHidden = false
            self.deleteButton.setTitle("Cancel", for: UIControlState())
            self.errorLabel.text = "Executing"

        case .Suspended:
            self.updateProgress(0)
            self.progressView.isHidden = true
            self.errorLabel.text = "Suspended"

        case .Finished:
            self.updateProgress(0) // Reset the progress bar to 0
            self.progressView.isHidden = true
            self.deleteButton.setTitle("Delete", for: UIControlState())

            if let error = self.descriptor?.error
            {
                self.errorLabel.text = error.localizedDescription
            }
            else
            {
                self.errorLabel.text = "Finished"
            }
        }
    }

    // MARK: KVO
    
    fileprivate func addObserversIfNecessary()
    {
        if let descriptor = self.descriptor, self.observersAdded == false
        {
            descriptor.addObserver(self, forKeyPath: type(of: self).StateKeyPath, options: .new, context: &self.stateKVOContext)
            descriptor.addObserver(self, forKeyPath: type(of: self).ProgressKeyPath, options: .new, context: &self.progressKVOContext)
            
            self.observersAdded = true
        }
    }
    
    fileprivate func removeObserversIfNecessary()
    {
        if let descriptor = self.descriptor, self.observersAdded == true
        {
            descriptor.removeObserver(self, forKeyPath: type(of: self).StateKeyPath, context: &self.stateKVOContext)
            descriptor.removeObserver(self, forKeyPath: type(of: self).ProgressKeyPath, context: &self.progressKVOContext)
            
            self.observersAdded = false
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?)
    {
        if let keyPath = keyPath
        {
            switch (keyPath, context)
            {
            case(type(of: self).ProgressKeyPath, self.progressKVOContext):
                
                let progress = (change?[NSKeyValueChangeKey.newKey] as AnyObject).doubleValue ?? 0;
                
                DispatchQueue.main.async(execute: { [weak self] () -> Void in
                    // Set the progress view to visible here so that the view has already been laid out
                    // And therefore the initial state is calculated based on the laid out width of the cell
                    // Doing this in awakeFromNib is too early, the width is incorrect [AH] 11/25/2015
                    self?.progressView.isHidden = false
                    self?.updateProgress(progress)
                })

            case(type(of: self).StateKeyPath, self.stateKVOContext):
                
                let stateRaw = (change?[NSKeyValueChangeKey.newKey] as? String) ?? DescriptorState.Ready.rawValue;
                let state = DescriptorState(rawValue: stateRaw)!

                DispatchQueue.main.async(execute: { [weak self] () -> Void in
                    self?.updateState(state)
                })

            default:
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }
        else
        {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}
